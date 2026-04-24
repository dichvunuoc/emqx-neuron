#!/usr/bin/env python3
import asyncio
import json
import os
import ssl

import websockets

COMMANDS = [
    {
        "commandId": "cmd_demo_get_nodes_20260423",
        "gatewayId": "gw_demo_001",
        "operation": "get_nodes",
        "neuronRequest": {"method": "GET", "path": "/api/v2/node", "query": {"type": 1}},
        "timeoutMs": 10000,
        "idempotencyKey": "gw_demo_001:get_nodes:demo",
        "dryRun": False,
        "createdAt": "2026-04-23T00:00:00Z",
    },
    {
        "commandId": "cmd_demo_get_groups_20260423",
        "gatewayId": "gw_demo_001",
        "operation": "get_groups",
        "neuronRequest": {"method": "GET", "path": "/api/v2/group"},
        "timeoutMs": 10000,
        "idempotencyKey": "gw_demo_001:get_groups:demo",
        "dryRun": False,
        "createdAt": "2026-04-23T00:00:00Z",
    },
    {
        "commandId": "cmd_demo_get_tags_20260423",
        "gatewayId": "gw_demo_001",
        "operation": "get_tags",
        "neuronRequest": {
            "method": "GET",
            "path": "/api/v2/tags",
            "query": {"node": "BL1_1", "group": "TSC"},
        },
        "timeoutMs": 10000,
        "idempotencyKey": "gw_demo_001:get_tags:demo",
        "dryRun": False,
        "createdAt": "2026-04-23T00:00:00Z",
    },
]


async def handler(websocket):
    print("client connected", flush=True)
    hello = await websocket.recv()
    print(f"recv {hello}", flush=True)
    await websocket.send(json.dumps({"type": "HELLO_ACK", "payload": {}}))
    for command in COMMANDS:
        await asyncio.sleep(1)
        await websocket.send(json.dumps({"type": "COMMAND", "payload": command}))
        response = await websocket.recv()
        print(f"response {response}", flush=True)
    await asyncio.sleep(1)


async def main():
    host = os.environ.get("CONTROL_SERVER_HOST", "0.0.0.0")
    port = int(os.environ.get("CONTROL_SERVER_PORT", "9010"))
    tls = os.environ.get("CONTROL_SERVER_TLS", "1") == "1"

    ssl_ctx = None
    scheme = "ws"
    if tls:
        cert_path = os.environ.get("CONTROL_SERVER_CERT", "/app/certs/server.crt")
        key_path = os.environ.get("CONTROL_SERVER_KEY", "/app/certs/server.key")
        ssl_ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ssl_ctx.load_cert_chain(cert_path, key_path)
        scheme = "wss"

    async with websockets.serve(handler, host, port, ssl=ssl_ctx):
        print(f"control server listening on {scheme}://{host}:{port}", flush=True)
        await asyncio.Future()


if __name__ == "__main__":
    asyncio.run(main())
