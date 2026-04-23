from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict

import jsonschema

from .agent_runner import AgentRunner
from .store import ConnectionStore


class RemoteControlService:
    def __init__(self, store: ConnectionStore, runner: AgentRunner, schema_path: Path) -> None:
        self.store = store
        self.runner = runner
        self.schema_doc = json.loads(schema_path.read_text(encoding="utf-8"))
        self.validator = jsonschema.Draft202012Validator(self.schema_doc)

    def get_profile(self) -> Dict[str, Any]:
        existing = self.store.load()
        if existing:
            return existing
        return {
            "enabled": False,
            "gatewayId": "gw_default_001",
            "controlServerUrl": "wss://control.example.com/reverse-channel",
            "authMode": "mtls",
            "hmacEnabled": False,
            "heartbeatSec": 20,
            "reconnectSec": 3,
            "dryRunDefault": True,
            "updatedAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        }

    def save_profile(self, payload: Dict[str, Any]) -> Dict[str, Any]:
        profile = {
            "enabled": False,
            "gatewayId": payload["gatewayId"],
            "controlServerUrl": payload["controlServerUrl"],
            "authMode": payload["authMode"],
            "hmacEnabled": bool(payload.get("hmacSecret")) or payload["authMode"] == "mtls_hmac",
            "heartbeatSec": payload["heartbeatSec"],
            "reconnectSec": payload["reconnectSec"],
            "dryRunDefault": payload.get("dryRunDefault", True),
            "description": payload.get("description", ""),
            "updatedAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        }
        self._validate_profile(profile)
        if payload.get("hmacSecret"):
            self.store.save_hmac_secret(payload["hmacSecret"])
        return self.store.save(profile)

    def test_connection(self, payload: Dict[str, Any]) -> Dict[str, Any]:
        profile = self.get_profile()
        merged = {
            "gatewayId": payload.get("gatewayId") or profile.get("gatewayId", ""),
            "controlServerUrl": payload.get("controlServerUrl") or profile.get("controlServerUrl", ""),
            "authMode": payload.get("authMode") or profile.get("authMode", "mtls"),
            "hmacSecret": payload.get("hmacSecret", ""),
        }

        if not merged["gatewayId"] or not merged["controlServerUrl"]:
            return {
                "ok": False,
                "code": "INVALID_CONFIG",
                "message": "gatewayId and controlServerUrl are required",
                "checkedAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            }
        if not str(merged["controlServerUrl"]).startswith("wss://"):
            return {
                "ok": False,
                "code": "INVALID_CONFIG",
                "message": "controlServerUrl must start with wss://",
                "checkedAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            }
        if merged["authMode"] == "mtls_hmac" and not (
            merged.get("hmacSecret") or self.store.load_hmac_secret()
        ):
            return {
                "ok": False,
                "code": "INVALID_CONFIG",
                "message": "hmacSecret is required when authMode is mtls_hmac",
                "checkedAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            }

        result = self.runner.test_connection(
            gateway_id=merged["gatewayId"],
            control_server_url=merged["controlServerUrl"],
            policy_version="v1",
            hmac_secret=merged.get("hmacSecret", ""),
        )
        result["checkedAt"] = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
        return result

    def connect(self) -> Dict[str, Any]:
        profile = self.get_profile()
        if not profile.get("gatewayId") or not profile.get("controlServerUrl"):
            return {"error": 1, "status": "failed", "message": "connection profile is incomplete"}
        if profile.get("authMode") == "mtls_hmac" and not self.store.load_hmac_secret():
            return {"error": 1, "status": "failed", "message": "missing hmac secret for mtls_hmac"}

        result = self.runner.connect(
            gateway_id=profile["gatewayId"],
            control_server_url=profile["controlServerUrl"],
            policy_version="v1",
            heartbeat_sec=profile["heartbeatSec"],
            reconnect_sec=profile["reconnectSec"],
            hmac_secret=self.store.load_hmac_secret(),
        )
        if result["status"] in {"connected", "connecting"}:
            profile["enabled"] = True
            self.store.save(profile)
        return result

    def disconnect(self) -> Dict[str, Any]:
        result = self.runner.disconnect()
        profile = self.get_profile()
        profile["enabled"] = False
        self.store.save(profile)
        return result

    def status(self) -> Dict[str, Any]:
        return self.runner.status()

    def _validate_profile(self, profile: Dict[str, Any]) -> None:
        errors = sorted(self.validator.iter_errors(profile), key=lambda err: err.path)
        if errors:
            raise ValueError(errors[0].message)
