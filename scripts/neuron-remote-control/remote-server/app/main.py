from __future__ import annotations

import asyncio
import secrets
import uuid
from datetime import datetime, timezone
from typing import Any, Dict, Optional

from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect
from pydantic import BaseModel, Field


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def err(code: str, message: str) -> Dict[str, str]:
    return {"errorCode": code, "message": message, "traceId": f"trace_{uuid.uuid4().hex}"}


class CreateEdgeGatewayRequest(BaseModel):
    edgeGatewayId: str = Field(min_length=3, max_length=128)
    siteCode: str
    displayName: Optional[str] = None
    authMode: str = Field(default="mtls", pattern="^(mtls|mtls_hmac)$")


class DispatchCommandRequest(BaseModel):
    commandId: str = Field(min_length=16, max_length=128)
    operation: str
    neuronRequest: Dict[str, Any]
    timeoutMs: int = Field(ge=1000, le=120000)
    idempotencyKey: str
    dryRun: bool = False


class RemoteState:
    def __init__(self) -> None:
        self.edge_gateways: Dict[str, Dict[str, Any]] = {}
        self.gateway_sockets: Dict[str, WebSocket] = {}
        self.commands: Dict[str, Dict[str, Any]] = {}
        self.pending: Dict[str, asyncio.Future] = {}
        self.lock = asyncio.Lock()
        self.control_server_url = "wss://remote-control.example.com/reverse-channel"

    async def mark_online(self, edge_gateway_id: str, ws: WebSocket) -> None:
        async with self.lock:
            if edge_gateway_id not in self.edge_gateways:
                self.edge_gateways[edge_gateway_id] = {
                    "edgeGatewayId": edge_gateway_id,
                    "siteCode": "unknown",
                    "displayName": edge_gateway_id,
                    "authMode": "mtls",
                    "createdAt": now_iso(),
                }
            self.gateway_sockets[edge_gateway_id] = ws
            self.edge_gateways[edge_gateway_id]["status"] = "online"
            self.edge_gateways[edge_gateway_id]["lastSeenAt"] = now_iso()

    async def mark_offline(self, edge_gateway_id: str, ws: WebSocket) -> None:
        async with self.lock:
            current = self.gateway_sockets.get(edge_gateway_id)
            if current is ws:
                self.gateway_sockets.pop(edge_gateway_id, None)
                gateway = self.edge_gateways.get(edge_gateway_id)
                if gateway:
                    gateway["status"] = "offline"
                    gateway["lastSeenAt"] = now_iso()


state = RemoteState()
app = FastAPI(title="Edge Gateway Remote Server", version="0.1.0")


@app.get("/health")
def health() -> Dict[str, str]:
    return {"status": "ok", "time": now_iso()}


@app.post("/v1/edge-gateways")
async def create_edge_gateway(req: CreateEdgeGatewayRequest) -> Dict[str, Any]:
    async with state.lock:
        if req.edgeGatewayId in state.edge_gateways:
            raise HTTPException(status_code=409, detail=err("CONFLICT", "edge gateway already exists"))
        created_at = now_iso()
        state.edge_gateways[req.edgeGatewayId] = {
            "edgeGatewayId": req.edgeGatewayId,
            "siteCode": req.siteCode,
            "displayName": req.displayName or req.edgeGatewayId,
            "authMode": req.authMode,
            "status": "offline",
            "createdAt": created_at,
            "lastSeenAt": None,
        }
        bootstrap: Dict[str, Any] = {
            "controlServerUrl": state.control_server_url,
            "authMode": req.authMode,
            "heartbeatSec": 20,
            "reconnectSec": 3,
        }
        if req.authMode == "mtls_hmac":
            bootstrap["hmacSecret"] = secrets.token_urlsafe(24)
        return {"edgeGatewayId": req.edgeGatewayId, "bootstrap": bootstrap, "createdAt": created_at}


@app.post("/v1/edge-gateways/{edge_gateway_id}/commands")
async def dispatch_command(edge_gateway_id: str, req: DispatchCommandRequest) -> Dict[str, Any]:
    async with state.lock:
        if edge_gateway_id not in state.edge_gateways:
            raise HTTPException(status_code=404, detail=err("NOT_FOUND", "edge gateway not found"))
        if req.commandId in state.commands:
            raise HTTPException(status_code=409, detail=err("CONFLICT", "commandId already exists"))
        ws = state.gateway_sockets.get(edge_gateway_id)
        if ws is None:
            raise HTTPException(status_code=409, detail=err("EDGE_OFFLINE", "edge gateway is not connected"))

        queued_at = now_iso()
        envelope = {
            "commandId": req.commandId,
            "gatewayId": edge_gateway_id,
            "operation": req.operation,
            "neuronRequest": req.neuronRequest,
            "timeoutMs": req.timeoutMs,
            "idempotencyKey": req.idempotencyKey,
            "dryRun": req.dryRun,
            "createdAt": queued_at,
        }
        state.commands[req.commandId] = {
            "edgeGatewayId": edge_gateway_id,
            "commandId": req.commandId,
            "status": "queued",
            "queuedAt": queued_at,
            "request": envelope,
        }
        loop = asyncio.get_running_loop()
        state.pending[req.commandId] = loop.create_future()

    try:
        await ws.send_json({"type": "COMMAND", "payload": envelope})
        async with state.lock:
            if req.commandId in state.commands:
                state.commands[req.commandId]["status"] = "running"
                state.commands[req.commandId]["startedAt"] = now_iso()
        asyncio.create_task(_timeout_watch(req.commandId, req.timeoutMs))
    except Exception as exc:
        async with state.lock:
            state.pending.pop(req.commandId, None)
            cmd = state.commands.get(req.commandId)
            if cmd:
                cmd["status"] = "failed"
                cmd["errorMessage"] = f"dispatch failed: {exc}"
                cmd["completedAt"] = now_iso()
        raise HTTPException(status_code=500, detail=err("DISPATCH_FAILED", str(exc))) from exc

    return {
        "edgeGatewayId": edge_gateway_id,
        "commandId": req.commandId,
        "status": "queued",
        "queuedAt": queued_at,
    }


@app.get("/v1/edge-gateways/{edge_gateway_id}/commands/{command_id}")
async def get_command(edge_gateway_id: str, command_id: str) -> Dict[str, Any]:
    async with state.lock:
        cmd = state.commands.get(command_id)
        if cmd is None or cmd.get("edgeGatewayId") != edge_gateway_id:
            raise HTTPException(status_code=404, detail=err("NOT_FOUND", "command not found"))
        return {
            "edgeGatewayId": cmd["edgeGatewayId"],
            "commandId": cmd["commandId"],
            "status": cmd["status"],
            "httpStatus": cmd.get("httpStatus"),
            "result": cmd.get("result"),
            "errorMessage": cmd.get("errorMessage"),
            "queuedAt": cmd.get("queuedAt"),
            "startedAt": cmd.get("startedAt"),
            "completedAt": cmd.get("completedAt"),
        }


@app.websocket("/reverse-channel")
async def reverse_channel(ws: WebSocket) -> None:
    await ws.accept()
    edge_gateway_id: Optional[str] = None
    try:
        while True:
            frame = await ws.receive_json()
            msg_type = frame.get("type")
            payload = frame.get("payload", {})
            if msg_type == "HELLO":
                edge_gateway_id = payload.get("gatewayId")
                if not edge_gateway_id:
                    await ws.close(code=1008)
                    return
                await state.mark_online(edge_gateway_id, ws)
                await ws.send_json({"type": "HELLO_ACK", "payload": {"serverTime": now_iso()}})
            elif msg_type == "HEARTBEAT":
                if edge_gateway_id:
                    async with state.lock:
                        gw = state.edge_gateways.get(edge_gateway_id)
                        if gw:
                            gw["lastSeenAt"] = now_iso()
                    await ws.send_json({"type": "PING_ACK", "payload": {}})
            elif msg_type == "RESPONSE":
                await _handle_response(payload)
    except WebSocketDisconnect:
        pass
    finally:
        if edge_gateway_id:
            await state.mark_offline(edge_gateway_id, ws)


async def _handle_response(payload: Dict[str, Any]) -> None:
    command_id = payload.get("commandId")
    if not command_id:
        return
    async with state.lock:
        cmd = state.commands.get(command_id)
        if cmd:
            cmd["status"] = payload.get("status", cmd["status"])
            cmd["httpStatus"] = payload.get("httpStatus")
            cmd["result"] = payload.get("result")
            cmd["errorMessage"] = payload.get("errorMessage")
            cmd["completedAt"] = payload.get("completedAt", now_iso())
        fut = state.pending.pop(command_id, None)
        if fut and not fut.done():
            fut.set_result(True)


async def _timeout_watch(command_id: str, timeout_ms: int) -> None:
    await asyncio.sleep(timeout_ms / 1000.0)
    async with state.lock:
        fut = state.pending.pop(command_id, None)
        cmd = state.commands.get(command_id)
        if fut and not fut.done():
            fut.set_result(False)
        if cmd and cmd.get("status") in {"queued", "running"}:
            cmd["status"] = "timeout"
            cmd["errorMessage"] = "command timeout"
            cmd["completedAt"] = now_iso()
