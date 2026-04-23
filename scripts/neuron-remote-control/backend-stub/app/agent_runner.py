from __future__ import annotations

import json
import os
import signal
import subprocess
import threading
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Optional


class AgentRunner:
    def __init__(self) -> None:
        self.agent_script = os.environ.get(
            "REMOTE_AGENT_SCRIPT",
            "scripts/neuron-remote-control/agent/gateway_agent.py",
        )
        self.schema_path = os.environ.get(
            "REMOTE_SCHEMA_PATH",
            "scripts/neuron-remote-control/contracts/command-envelope.schema.json",
        )
        self.neuron_base_url = os.environ.get("REMOTE_NEURON_BASE_URL", "http://127.0.0.1:7000")
        self.neuron_token = os.environ.get("REMOTE_NEURON_TOKEN", "")

        self._process: Optional[subprocess.Popen[str]] = None
        self._lock = threading.Lock()
        self._last_heartbeat_at: Optional[datetime] = None
        self._last_error: Optional[str] = None
        self._state = "disabled"
        self._last_change_at = datetime.now(timezone.utc)

    def _set_state(self, state: str, last_error: Optional[str] = None) -> None:
        self._state = state
        self._last_error = last_error
        self._last_change_at = datetime.now(timezone.utc)

    def test_connection(
        self,
        gateway_id: str,
        control_server_url: str,
        policy_version: str = "v1",
        hmac_secret: str = "",
    ) -> Dict[str, Any]:
        started = time.time()
        cmd = [
            "python3",
            self.agent_script,
            "--test-router",
            "--router-url",
            control_server_url,
            "--gateway-id",
            gateway_id,
            "--schema",
            self.schema_path,
            "--neuron-base-url",
            self.neuron_base_url,
            "--neuron-token",
            self.neuron_token,
            "--policy-version",
            policy_version,
        ]
        if hmac_secret:
            cmd.extend(["--hmac-secret", hmac_secret])

        proc = subprocess.run(cmd, capture_output=True, text=True)
        latency = int((time.time() - started) * 1000)
        if proc.returncode == 0:
            return {
                "ok": True,
                "code": "CONNECTED",
                "message": "router reachable and acknowledged HELLO",
                "latencyMs": latency,
            }

        err = (proc.stderr or proc.stdout or "connection test failed").strip()
        code = "ROUTER_NO_ACK"
        lowered = err.lower()
        if "certificate" in lowered or "ssl" in lowered or "tls" in lowered:
            code = "TLS_FAILED"
        elif "401" in lowered or "403" in lowered or "auth" in lowered:
            code = "AUTH_FAILED"
        elif "timeout" in lowered:
            code = "TIMEOUT"
        return {"ok": False, "code": code, "message": err, "latencyMs": latency}

    def connect(
        self,
        gateway_id: str,
        control_server_url: str,
        policy_version: str,
        heartbeat_sec: int,
        reconnect_sec: int,
        hmac_secret: str,
    ) -> Dict[str, Any]:
        with self._lock:
            if self._process and self._process.poll() is None:
                self._set_state("connected")
                return {
                    "error": 0,
                    "status": "connected",
                    "message": "agent already running",
                }

            cmd = [
                "python3",
                self.agent_script,
                "--run-loop",
                "--router-url",
                control_server_url,
                "--gateway-id",
                gateway_id,
                "--schema",
                self.schema_path,
                "--neuron-base-url",
                self.neuron_base_url,
                "--neuron-token",
                self.neuron_token,
                "--policy-version",
                policy_version,
                "--heartbeat-sec",
                str(heartbeat_sec),
                "--reconnect-sec",
                str(reconnect_sec),
            ]
            if hmac_secret:
                cmd.extend(["--hmac-secret", hmac_secret])

            self._set_state("connecting")
            self._process = subprocess.Popen(
                cmd,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.PIPE,
                text=True,
            )
            time.sleep(0.3)
            if self._process.poll() is not None:
                err = self._process.stderr.read().strip() if self._process.stderr else "agent start failed"
                self._set_state("failed", last_error=err)
                return {"error": 1, "status": "failed", "message": err}

            self._last_heartbeat_at = datetime.now(timezone.utc)
            self._set_state("connected")
            return {"error": 0, "status": "connected", "message": "agent connected"}

    def disconnect(self) -> Dict[str, Any]:
        with self._lock:
            if not self._process or self._process.poll() is not None:
                self._set_state("disconnected")
                return {"error": 0, "status": "disconnected", "message": "already stopped"}

            self._process.send_signal(signal.SIGTERM)
            try:
                self._process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                self._process.kill()
            self._process = None
            self._set_state("disconnected")
            return {"error": 0, "status": "disconnected", "message": "agent stopped"}

    def status(self) -> Dict[str, Any]:
        with self._lock:
            if self._process and self._process.poll() is not None and self._state == "connected":
                err = self._process.stderr.read().strip() if self._process.stderr else "agent process exited"
                self._set_state("degraded", last_error=err)

            return {
                "state": self._state,
                "lastError": self._last_error,
                "lastHeartbeatAt": self._to_iso(self._last_heartbeat_at),
                "lastChangeAt": self._to_iso(self._last_change_at),
            }

    @staticmethod
    def _to_iso(dt: Optional[datetime]) -> Optional[str]:
        if dt is None:
            return None
        return dt.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")
