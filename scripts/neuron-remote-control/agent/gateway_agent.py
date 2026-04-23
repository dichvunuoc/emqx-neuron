#!/usr/bin/env python3
"""GatewayAgent for Neuron reverse-channel execution.

Capabilities:
- Validate incoming command against JSON schema
- Verify command HMAC signature (optional but recommended)
- Enforce operation/path allowlist
- Inject local Neuron Authorization token
- Execute local HTTP request to Neuron API
- Run WebSocket reverse-channel loop (HELLO/HEARTBEAT/COMMAND/RESPONSE)
"""

from __future__ import annotations

import argparse
import hashlib
import hmac
import json
import logging
import os
import ssl
import sys
import time
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Optional, Tuple
from urllib import parse, request
from urllib.error import HTTPError, URLError

try:
    import jsonschema
except Exception as exc:  # pragma: no cover
    raise SystemExit(
        "Missing dependency: jsonschema. Install with `pip install jsonschema`."
    ) from exc

try:
    import websocket
except Exception as exc:  # pragma: no cover
    raise SystemExit(
        "Missing dependency: websocket-client. Install with `pip install websocket-client`."
    ) from exc


LOG = logging.getLogger("gateway-agent")

ALLOWED_OPERATIONS: Dict[str, Tuple[str, str]] = {
    "get_version": ("GET", "/api/v2/version"),
    "get_nodes": ("GET", "/api/v2/node"),
    "get_node_state": ("GET", "/api/v2/node/state"),
    "get_node_setting": ("GET", "/api/v2/node/setting"),
    "get_groups": ("GET", "/api/v2/group"),
    "get_tags": ("GET", "/api/v2/tags"),
    "get_subscribe": ("GET", "/api/v2/subscribe"),
    "get_subscribes": ("GET", "/api/v2/subscribes"),
    "read_tags": ("POST", "/api/v2/read"),
    "create_subscribe": ("POST", "/api/v2/subscribe"),
    "update_subscribe": ("PUT", "/api/v2/subscribe"),
    "delete_subscribe": ("DELETE", "/api/v2/subscribe"),
    "create_group": ("POST", "/api/v2/group"),
    "update_group": ("PUT", "/api/v2/group"),
    "delete_group": ("DELETE", "/api/v2/group"),
    "create_tags": ("POST", "/api/v2/tags"),
    "update_tags": ("PUT", "/api/v2/tags"),
    "delete_tags": ("DELETE", "/api/v2/tags"),
    "node_ctl": ("POST", "/api/v2/node/ctl"),
}

WRITE_OPERATIONS = {
    "create_subscribe",
    "update_subscribe",
    "delete_subscribe",
    "create_group",
    "update_group",
    "delete_group",
    "create_tags",
    "update_tags",
    "delete_tags",
    "node_ctl",
}


@dataclass
class AgentConfig:
    gateway_id: str
    neuron_base_url: str
    neuron_token: str
    policy_version: str = "v1"
    hmac_secret: str = ""


class CommandRejected(Exception):
    """Raised when command violates policy."""


class GatewayAgent:
    def __init__(self, config: AgentConfig, command_schema_path: Path) -> None:
        self.config = config
        schema_doc = json.loads(command_schema_path.read_text(encoding="utf-8"))
        self.command_validator = jsonschema.Draft202012Validator(schema_doc)

    def execute_command(self, envelope: Dict[str, Any], signature: Optional[str] = None) -> Dict[str, Any]:
        started = time.time()
        command_id = envelope.get("commandId", "unknown")
        LOG.info("execute command=%s operation=%s", command_id, envelope.get("operation"))

        self._validate_envelope(envelope)
        self._verify_signature(envelope, signature)
        self._enforce_policy(envelope)

        if envelope.get("dryRun", False) and envelope["operation"] in WRITE_OPERATIONS:
            return self._build_response(
                envelope=envelope,
                status="success",
                http_status=200,
                result={"dryRun": True, "message": "write command validation passed"},
                started=started,
                signature_verified=bool(self.config.hmac_secret),
            )

        http_status, payload, error_code, error_message = self._call_neuron(envelope)
        status = "success" if 200 <= http_status < 300 and error_message is None else "failed"
        return self._build_response(
            envelope=envelope,
            status=status,
            http_status=http_status,
            result=payload,
            error_code=error_code,
            error_message=error_message,
            started=started,
            signature_verified=bool(self.config.hmac_secret),
        )

    def _validate_envelope(self, envelope: Dict[str, Any]) -> None:
        errors = sorted(self.command_validator.iter_errors(envelope), key=lambda item: item.path)
        if errors:
            raise CommandRejected(f"schema validation failed: {errors[0].message}")

    def _verify_signature(self, envelope: Dict[str, Any], signature: Optional[str]) -> None:
        if not self.config.hmac_secret:
            return
        if not signature:
            raise CommandRejected("missing x-signature for signed mode")

        canonical = self._canonical_command(envelope)
        expected = hmac.new(
            self.config.hmac_secret.encode("utf-8"),
            canonical.encode("utf-8"),
            hashlib.sha256,
        ).hexdigest()
        if not hmac.compare_digest(expected, signature):
            raise CommandRejected("invalid command signature")

    @staticmethod
    def _canonical_command(envelope: Dict[str, Any]) -> str:
        return json.dumps(envelope, sort_keys=True, separators=(",", ":"), ensure_ascii=True)

    def _enforce_policy(self, envelope: Dict[str, Any]) -> None:
        if envelope.get("gatewayId") != self.config.gateway_id:
            raise CommandRejected("gatewayId mismatch")

        operation = envelope["operation"]
        if operation not in ALLOWED_OPERATIONS:
            raise CommandRejected(f"operation not allowlisted: {operation}")

        req = envelope["neuronRequest"]
        expected_method, expected_path = ALLOWED_OPERATIONS[operation]
        if req["method"] != expected_method or req["path"] != expected_path:
            raise CommandRejected("method/path does not match operation allowlist")

        for header_name in req.get("headers", {}):
            if header_name.lower() == "authorization":
                raise CommandRejected("authorization header cannot be provided by caller")

        now = datetime.now(tz=timezone.utc)
        expires_at = envelope.get("expiresAt")
        if expires_at:
            expires_dt = datetime.fromisoformat(expires_at.replace("Z", "+00:00"))
            if now >= expires_dt:
                raise CommandRejected("command expired")

    def _call_neuron(self, envelope: Dict[str, Any]) -> Tuple[int, Any, int | None, str | None]:
        req = envelope["neuronRequest"]
        query = req.get("query", {})
        encoded_qs = parse.urlencode(query) if query else ""
        url = f"{self.config.neuron_base_url}{req['path']}"
        if encoded_qs:
            url = f"{url}?{encoded_qs}"

        body = req.get("body")
        data = None
        headers = {
            "Accept": "application/json",
            "Authorization": f"Bearer {self.config.neuron_token}",
        }
        if body is not None:
            data = json.dumps(body).encode("utf-8")
            headers["Content-Type"] = "application/json"

        for key, value in req.get("headers", {}).items():
            headers[key] = value

        timeout_sec = envelope["timeoutMs"] / 1000.0
        http_req = request.Request(url=url, method=req["method"], headers=headers, data=data)

        try:
            with request.urlopen(http_req, timeout=timeout_sec) as resp:
                content = resp.read().decode("utf-8")
                payload = json.loads(content) if content else None
                return resp.status, payload, self._extract_neuron_error_code(payload), None
        except HTTPError as exc:
            content = exc.read().decode("utf-8") if exc.fp else ""
            payload = self._safe_json(content)
            return exc.code, payload, self._extract_neuron_error_code(payload), str(exc)
        except URLError as exc:
            return 503, None, None, str(exc)

    @staticmethod
    def _safe_json(text: str) -> Any:
        try:
            return json.loads(text)
        except Exception:
            return {"raw": text}

    @staticmethod
    def _extract_neuron_error_code(payload: Any) -> int | None:
        if isinstance(payload, dict) and "error" in payload and isinstance(payload["error"], int):
            return payload["error"]
        return None

    def _build_response(
        self,
        envelope: Dict[str, Any],
        status: str,
        http_status: int,
        result: Any,
        started: float,
        signature_verified: bool,
        error_code: int | None = None,
        error_message: str | None = None,
    ) -> Dict[str, Any]:
        completed = time.time()
        started_dt = datetime.fromtimestamp(started, tz=timezone.utc)
        completed_dt = datetime.fromtimestamp(completed, tz=timezone.utc)

        response: Dict[str, Any] = {
            "commandId": envelope["commandId"],
            "gatewayId": envelope["gatewayId"],
            "status": status,
            "attempt": 1,
            "httpStatus": http_status,
            "result": result,
            "validation": {
                "policyVersion": self.config.policy_version,
                "allowlistMatched": True,
                "signatureVerified": signature_verified,
            },
            "startedAt": started_dt.isoformat().replace("+00:00", "Z"),
            "completedAt": completed_dt.isoformat().replace("+00:00", "Z"),
            "durationMs": int((completed - started) * 1000),
            "traceId": f"trace_{uuid.uuid4().hex}",
        }
        if error_code is not None:
            response["neuronErrorCode"] = error_code
        if error_message:
            response["errorMessage"] = error_message
        return response


class ReverseChannelClient:
    def __init__(
        self,
        agent: GatewayAgent,
        router_url: str,
        heartbeat_sec: int = 20,
        reconnect_sec: int = 3,
    ) -> None:
        self.agent = agent
        self.router_url = router_url
        self.heartbeat_sec = heartbeat_sec
        self.reconnect_sec = reconnect_sec

    def run_forever(self) -> None:
        while True:
            ws = None
            try:
                LOG.info("connecting router=%s", self.router_url)
                ws = websocket.create_connection(
                    self.router_url,
                    timeout=30,
                    sslopt=_insecure_sslopt(),
                )
                self._send_hello(ws)
                last_ping = time.time()

                while True:
                    if time.time() - last_ping >= self.heartbeat_sec:
                        self._send_heartbeat(ws)
                        last_ping = time.time()

                    ws.settimeout(1)
                    try:
                        raw = ws.recv()
                    except websocket.WebSocketTimeoutException:
                        continue

                    if not raw:
                        raise ConnectionError("router connection closed")
                    self._handle_frame(ws, raw)
            except KeyboardInterrupt:
                LOG.info("stopping reverse channel")
                break
            except Exception as exc:
                LOG.warning("reverse channel disconnected: %s", exc)
                time.sleep(self.reconnect_sec)
            finally:
                if ws is not None:
                    try:
                        ws.close()
                    except Exception:
                        pass

    def _send_hello(self, ws: websocket.WebSocket) -> None:
        hello = {
            "type": "HELLO",
            "payload": {
                "gatewayId": self.agent.config.gateway_id,
                "agentVersion": "0.2.0",
                "policyVersion": self.agent.config.policy_version,
                "capabilities": {
                    "signedCommands": bool(self.agent.config.hmac_secret),
                    "dryRun": True,
                    "operations": list(ALLOWED_OPERATIONS.keys()),
                },
            },
        }
        ws.send(json.dumps(hello, ensure_ascii=True))
        LOG.info("HELLO sent")

    def _send_heartbeat(self, ws: websocket.WebSocket) -> None:
        heartbeat = {
            "type": "HEARTBEAT",
            "payload": {
                "gatewayId": self.agent.config.gateway_id,
                "ts": datetime.now(tz=timezone.utc).isoformat().replace("+00:00", "Z"),
            },
        }
        ws.send(json.dumps(heartbeat, ensure_ascii=True))

    def _handle_frame(self, ws: websocket.WebSocket, raw: str) -> None:
        frame = json.loads(raw)
        msg_type = frame.get("type")
        if msg_type in {"HELLO_ACK", "PING_ACK"}:
            return
        if msg_type == "COMMAND":
            envelope = frame.get("payload", {})
            signature = frame.get("signature")
            response = self._execute_with_rejection(envelope, signature)
            outbound = {
                "type": "RESPONSE",
                "payload": response,
            }
            ws.send(json.dumps(outbound, ensure_ascii=True))
            return
        LOG.debug("ignored frame type=%s", msg_type)

    def _execute_with_rejection(self, envelope: Dict[str, Any], signature: Optional[str]) -> Dict[str, Any]:
        try:
            return self.agent.execute_command(envelope, signature=signature)
        except CommandRejected as exc:
            now = datetime.now(tz=timezone.utc).isoformat().replace("+00:00", "Z")
            return {
                "commandId": envelope.get("commandId", "unknown"),
                "gatewayId": envelope.get("gatewayId", self.agent.config.gateway_id),
                "status": "rejected",
                "attempt": 1,
                "httpStatus": 400,
                "errorMessage": str(exc),
                "validation": {
                    "policyVersion": self.agent.config.policy_version,
                    "allowlistMatched": False,
                    "signatureVerified": False,
                },
                "startedAt": now,
                "completedAt": now,
                "durationMs": 0,
                "traceId": f"trace_{uuid.uuid4().hex}",
            }


def _load_json(path: Path) -> Dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def _insecure_sslopt() -> Dict[str, Any]:
    if os.environ.get("REMOTE_TLS_INSECURE", "0") == "1":
        return {"cert_reqs": ssl.CERT_NONE, "check_hostname": False}
    return {}


def _single_command_mode(args: argparse.Namespace) -> int:
    command_path = Path(args.command).resolve()
    schema_path = Path(args.schema).resolve()

    config = AgentConfig(
        gateway_id=args.gateway_id,
        neuron_base_url=args.neuron_base_url.rstrip("/"),
        neuron_token=args.neuron_token,
        policy_version=args.policy_version,
        hmac_secret=args.hmac_secret,
    )
    agent = GatewayAgent(config=config, command_schema_path=schema_path)
    envelope = _load_json(command_path)

    try:
        response = agent.execute_command(envelope, signature=args.signature)
        print(json.dumps(response, ensure_ascii=True, indent=2))
        return 0
    except CommandRejected as exc:
        now = datetime.now(tz=timezone.utc).isoformat().replace("+00:00", "Z")
        rejection = {
            "commandId": envelope.get("commandId", "unknown"),
            "gatewayId": envelope.get("gatewayId", "unknown"),
            "status": "rejected",
            "attempt": 1,
            "httpStatus": 400,
            "errorMessage": str(exc),
            "validation": {
                "policyVersion": args.policy_version,
                "allowlistMatched": False,
                "signatureVerified": False,
            },
            "startedAt": now,
            "completedAt": now,
            "durationMs": 0,
        }
        print(json.dumps(rejection, ensure_ascii=True, indent=2))
        return 2


def _reverse_channel_mode(args: argparse.Namespace) -> int:
    if not args.router_url:
        raise SystemExit("--router-url is required for --run-loop mode")

    schema_path = Path(args.schema).resolve()
    config = AgentConfig(
        gateway_id=args.gateway_id,
        neuron_base_url=args.neuron_base_url.rstrip("/"),
        neuron_token=args.neuron_token,
        policy_version=args.policy_version,
        hmac_secret=args.hmac_secret,
    )
    agent = GatewayAgent(config=config, command_schema_path=schema_path)
    client = ReverseChannelClient(
        agent=agent,
        router_url=args.router_url,
        heartbeat_sec=args.heartbeat_sec,
        reconnect_sec=args.reconnect_sec,
    )
    client.run_forever()
    return 0


def _test_router_mode(args: argparse.Namespace) -> int:
    if not args.router_url:
        raise SystemExit("--router-url is required for --test-router mode")
    ws = websocket.create_connection(
        args.router_url,
        timeout=10,
        sslopt=_insecure_sslopt(),
    )
    try:
        hello = {
            "type": "HELLO",
            "payload": {
                "gatewayId": args.gateway_id,
                "agentVersion": "0.2.0",
                "policyVersion": args.policy_version,
                "capabilities": {
                    "signedCommands": bool(args.hmac_secret),
                    "dryRun": True,
                    "operations": list(ALLOWED_OPERATIONS.keys()),
                },
            },
        }
        ws.send(json.dumps(hello, ensure_ascii=True))
        ws.settimeout(5)
        raw = ws.recv()
        frame = json.loads(raw) if raw else {}
        print(
            json.dumps(
                {
                    "ok": frame.get("type") in {"HELLO_ACK", "PING_ACK"},
                    "receivedType": frame.get("type"),
                    "message": "router reachable and responded",
                },
                ensure_ascii=True,
                indent=2,
            )
        )
        return 0
    finally:
        ws.close()


def main() -> int:
    parser = argparse.ArgumentParser(description="GatewayAgent for Neuron reverse-channel")
    parser.add_argument(
        "--schema",
        default="../contracts/command-envelope.schema.json",
        help="Path to command envelope schema",
    )
    parser.add_argument("--gateway-id", required=True)
    parser.add_argument("--neuron-base-url", default="http://127.0.0.1:7000")
    parser.add_argument("--neuron-token", required=True)
    parser.add_argument("--policy-version", default="v1")
    parser.add_argument("--hmac-secret", default="", help="Shared secret for x-signature verification")

    parser.add_argument("--command", help="Path to command envelope JSON (single execution mode)")
    parser.add_argument("--signature", help="HMAC signature for --command payload")

    parser.add_argument("--run-loop", action="store_true", help="Run reverse channel websocket loop")
    parser.add_argument("--test-router", action="store_true", help="Test router reachability with HELLO handshake")
    parser.add_argument("--router-url", help="WSS URL of ReverseChannelRouter")
    parser.add_argument("--heartbeat-sec", type=int, default=20)
    parser.add_argument("--reconnect-sec", type=int, default=3)
    args = parser.parse_args()

    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

    if args.test_router:
        return _test_router_mode(args)
    if args.run_loop:
        return _reverse_channel_mode(args)
    if not args.command:
        raise SystemExit("Use --command for single mode or --run-loop for websocket mode")
    return _single_command_mode(args)


if __name__ == "__main__":
    sys.exit(main())
