#!/usr/bin/env python3
"""
Warm up MQTT "full-table-on-change" behavior on an existing Neuron deployment.

Why this exists:
- On long-lived edge persistence, MQTT app + subscriptions may keep older runtime state.
- After toggling "Full Table On Change", operators may still see partial payloads until
  driver/MQTT runtime is restarted and fresh reads happen.

What this script does:
1) Login to Neuron API
2) Force full-table-on-change=true for one MQTT app
3) Stop MQTT app
4) Restart all south nodes (type=1) to trigger fresh reads
5) Start MQTT app again
"""

from __future__ import annotations

import argparse
import json
import sys
import urllib.error
import urllib.parse
import urllib.request
from typing import Any, Dict, List


def api_request(base: str, token: str, path: str, method: str = "GET", body: Dict[str, Any] | None = None) -> Dict[str, Any]:
    data = None if body is None else json.dumps(body).encode("utf-8")
    headers = {"Accept": "application/json"}
    if data is not None:
        headers["Content-Type"] = "application/json"
    if token:
        headers["Authorization"] = f"Bearer {token}"

    req = urllib.request.Request(f"{base}{path}", data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            raw = resp.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", errors="replace")
        raise SystemExit(f"{method} {path} failed HTTP {e.code}: {raw}") from e
    except urllib.error.URLError as e:
        raise SystemExit(f"{method} {path} failed: {e.reason}") from e
    return json.loads(raw) if raw.strip() else {}


def login(base: str, user: str, password: str) -> str:
    req = urllib.request.Request(
        f"{base}/api/v2/login",
        data=json.dumps({"name": user, "pass": password}).encode("utf-8"),
        method="POST",
        headers={"Content-Type": "application/json", "Accept": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=20) as resp:
        payload = json.loads(resp.read().decode("utf-8", errors="replace"))
    token = payload.get("token", "")
    if not token:
        raise SystemExit(f"Login succeeded but no token in response: {payload}")
    return token


def node_ctl(base: str, token: str, node: str, cmd: int) -> None:
    api_request(base, token, "/api/v2/node/ctl", "POST", {"node": node, "cmd": cmd})


def main() -> int:
    p = argparse.ArgumentParser(description="Warm up MQTT full-table-on-change on edge runtime.")
    p.add_argument("--base-url", default="http://127.0.0.1", help="Neuron API base URL (default: http://127.0.0.1)")
    p.add_argument("--user", default="admin", help="Neuron user (default: admin)")
    p.add_argument("--password", default="0000", help="Neuron password (default: 0000)")
    p.add_argument("--mqtt-app", default="mqtt-hoanhbo", help="MQTT app/node name (default: mqtt-hoanhbo)")
    args = p.parse_args()

    base = args.base_url.rstrip("/")
    token = login(base, args.user, args.password)

    setting = api_request(base, token, f"/api/v2/node/setting?node={urllib.parse.quote(args.mqtt_app)}", "GET")
    params = setting.get("params") or {}
    params["full-table-on-change"] = True
    api_request(base, token, "/api/v2/node/setting", "POST", {"node": args.mqtt_app, "params": params})
    print(f"[OK] full-table-on-change=true for {args.mqtt_app}")

    node_ctl(base, token, args.mqtt_app, 1)
    print(f"[OK] stopped {args.mqtt_app}")

    south_nodes: List[Dict[str, Any]] = api_request(base, token, "/api/v2/node?type=1", "GET").get("nodes", [])
    names = [str(n.get("name", "")).strip() for n in south_nodes if str(n.get("name", "")).strip()]

    for n in names:
        try:
            node_ctl(base, token, n, 1)
        except SystemExit:
            pass
    for n in names:
        try:
            node_ctl(base, token, n, 0)
        except SystemExit:
            pass
    print(f"[OK] restarted south nodes: {len(names)}")

    node_ctl(base, token, args.mqtt_app, 0)
    print(f"[OK] started {args.mqtt_app}")
    print("[DONE] warm-up completed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
