#!/usr/bin/env python3
"""
Discover south drivers (GET /api/v2/node?type=1), list groups per driver, then
POST /api/v2/subscribes with MQTT topics:

  ioc/{site_slug}/{module_id}/{device_slug}/{data_type}

Default: site=quang-ninh, module_id=mod-01.. by sorted driver name, device_slug=slug(group),
data_type=telemetry.

JWT / login API
  Same as Dashboard: POST /api/v2/login with JSON {"name":"admin","pass":"..."}.
  Minimal curl (browser Cookie headers are not required by Neuron):

    curl -sS 'http://localhost:7001/api/v2/login' \\
      -H 'Accept: application/json' \\
      -H 'Content-Type: application/json' \\
      --data-raw '{"name":"admin","pass":"0000"}'

  Response JSON includes "token" (JWT). Use with this script: --token "$TOKEN", or
  --user admin --password 0000 (no curl needed).

Batching JSON payloads on MQTT is configured in the north MQTT plugin (custom format),
not by this API — see OPERATOR_NOTES.txt and examples/mqtt_custom_upload_format.json.

Stdlib only (no pip deps).
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from typing import Any, Dict, List, Optional, Tuple

DEFAULT_SITE = "quang-ninh"
DEFAULT_DATA_TYPE = "telemetry"
INVALID_TOPIC_CHARS = re.compile(r"[#+]")


def slug(s: str) -> str:
    s = (s or "").strip().lower()
    s = re.sub(r"\s+", "-", s)
    s = re.sub(r"[^a-z0-9._-]+", "-", s)
    s = re.sub(r"-+", "-", s).strip("-")
    return s


def build_ioc_topic(
    *,
    site: str,
    module_id: str,
    device_slug: str,
    data_type: str,
) -> str:
    site_f = slug(site) if site else slug(DEFAULT_SITE)
    dt = slug(data_type) if data_type else DEFAULT_DATA_TYPE
    if not dt:
        dt = DEFAULT_DATA_TYPE
    parts = ["ioc", site_f, module_id, device_slug, dt]
    topic = "/".join(parts)
    if INVALID_TOPIC_CHARS.search(topic):
        raise ValueError(f"Topic contains invalid MQTT wildcard chars: {topic!r}")
    return topic


def http_request_json(
    url: str,
    method: str,
    token: Optional[str],
    body: Optional[Dict[str, Any]] = None,
    timeout: float = 120.0,
) -> Tuple[int, Dict[str, Any]]:
    data: Optional[bytes] = None
    headers: Dict[str, str] = {"Accept": "application/json"}
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        headers["Content-Type"] = "application/json"
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(url, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read().decode("utf-8", errors="replace")
            code = resp.getcode()
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", errors="replace")
        code = e.code
    except urllib.error.URLError as e:
        raise SystemExit(f"HTTP request failed ({method} {url}): {e.reason}") from e
    try:
        parsed: Dict[str, Any] = json.loads(raw) if raw.strip() else {}
    except json.JSONDecodeError:
        parsed = {"_raw": raw}
    return code, parsed


def http_get_json(url: str, token: str, timeout: float = 120.0) -> Tuple[int, Dict[str, Any]]:
    return http_request_json(url, "GET", token, body=None, timeout=timeout)


def http_post_json(
    url: str, token: str, body: Dict[str, Any], timeout: float = 120.0
) -> Tuple[int, Dict[str, Any]]:
    return http_request_json(url, "POST", token, body=body, timeout=timeout)


def login(base: str, user: str, password: str) -> str:
    url = f"{base.rstrip('/')}/api/v2/login"
    code, resp = http_post_json(url, "", {"name": user, "pass": password})
    if code != 200:
        raise SystemExit(f"login failed HTTP {code}: {resp}")
    token = resp.get("token")
    if not token:
        raise SystemExit(f"login response missing token: {resp}")
    return str(token)


@dataclass
class SubscribeEntry:
    driver: str
    group: str
    topic: str
    module_id: str


def fetch_south_nodes(
    base: str, token: str, plugin_filter: Optional[str]
) -> List[Dict[str, Any]]:
    q = urllib.parse.urlencode({"type": "1"})
    url = f"{base.rstrip('/')}/api/v2/node?{q}"
    code, resp = http_get_json(url, token)
    if code != 200:
        raise SystemExit(f"GET node failed HTTP {code}: {resp}")
    nodes = resp.get("nodes")
    if not isinstance(nodes, list):
        raise SystemExit(f"unexpected nodes response: {resp}")
    out: List[Dict[str, Any]] = []
    for n in nodes:
        if not isinstance(n, dict):
            continue
        plugin = str(n.get("plugin", ""))
        if plugin_filter and plugin_filter.lower() not in plugin.lower():
            continue
        out.append(n)
    return out


def fetch_groups(base: str, token: str, node: str) -> List[str]:
    q = urllib.parse.urlencode({"node": node})
    url = f"{base.rstrip('/')}/api/v2/group?{q}"
    code, resp = http_get_json(url, token)
    if code != 200:
        raise SystemExit(f"GET group node={node!r} failed HTTP {code}: {resp}")
    groups = resp.get("groups")
    if not isinstance(groups, list):
        raise SystemExit(f"unexpected groups for {node!r}: {resp}")
    names: List[str] = []
    for g in groups:
        if isinstance(g, dict) and g.get("name"):
            names.append(str(g["name"]))
    return names


def module_map_for_drivers(driver_names: List[str]) -> Dict[str, str]:
    sorted_names = sorted(driver_names)
    m: Dict[str, str] = {}
    for i, name in enumerate(sorted_names, start=1):
        m[name] = f"mod-{i:02d}"
    return m


def build_entries(
    nodes: List[Dict[str, Any]],
    base: str,
    token: str,
    site: str,
    data_type: str,
    fail_on_overflow: bool,
) -> Tuple[List[SubscribeEntry], List[str]]:
    warnings: List[str] = []
    names = [str(n["name"]) for n in nodes if n.get("name")]
    mod_map = module_map_for_drivers(names)
    if len(mod_map) > 12:
        msg = (
            f"Found {len(mod_map)} south drivers; ISA-95 plan referenced mod-01..mod-12 only. "
            f"Module ids will continue as mod-13, mod-14, ..."
        )
        warnings.append(msg)
        if fail_on_overflow:
            raise SystemExit(msg)

    entries: List[SubscribeEntry] = []
    for n in sorted(nodes, key=lambda x: str(x.get("name", ""))):
        driver = str(n.get("name", ""))
        if not driver:
            continue
        mid = mod_map[driver]
        for gname in fetch_groups(base, token, driver):
            dev = slug(gname)
            if not dev:
                warnings.append(f"Skip empty slug for group {gname!r} on {driver!r}")
                continue
            topic = build_ioc_topic(
                site=site,
                module_id=mid,
                device_slug=dev,
                data_type=data_type,
            )
            entries.append(
                SubscribeEntry(
                    driver=driver,
                    group=gname,
                    topic=topic,
                    module_id=mid,
                )
            )
    return entries, warnings


def run(args: argparse.Namespace) -> int:
    base = args.base_url.rstrip("/")
    if args.token:
        token = args.token.strip()
    else:
        if not args.user or args.password is None:
            print("Need --token or both --user and --password", file=sys.stderr)
            return 1
        token = login(base, args.user, args.password)

    nodes = fetch_south_nodes(base, token, args.plugin_filter)
    if not nodes:
        print("No south nodes (type=1) after filter.", file=sys.stderr)
        return 1

    entries, warnings = build_entries(
        nodes,
        base,
        token,
        site=args.site,
        data_type=args.data_type,
        fail_on_overflow=args.fail_on_module_overflow,
    )
    for w in warnings:
        print(f"Warning: {w}", file=sys.stderr)

    if not entries:
        print("No driver/group pairs to subscribe.", file=sys.stderr)
        return 1

    # Preview
    show = min(5, len(entries))
    for e in entries[:show]:
        print(f"  {e.driver}/{e.group} [{e.module_id}] -> {e.topic}")
    if len(entries) > show:
        print(f"  ... and {len(entries) - show} more")

    if args.dry_run:
        print("Dry run: no POST /api/v2/subscribes")
        return 0

    batch = max(1, int(args.batch_size))
    url = f"{base}/api/v2/subscribes"
    for i in range(0, len(entries), batch):
        chunk = entries[i : i + batch]
        groups_payload = [
            {"driver": e.driver, "group": e.group, "params": {"topic": e.topic}}
            for e in chunk
        ]
        body = {"app": args.app, "groups": groups_payload}
        code, resp = http_post_json(url, token, body)
        err = resp.get("error", -1)
        if code != 200 or err != 0:
            print(
                f"subscribes POST failed HTTP {code} error={err} body={resp}",
                file=sys.stderr,
            )
            return 1
        print(f"subscribes OK rows {i + 1}-{i + len(chunk)} / {len(entries)}")

    return 0


def main() -> int:
    p = argparse.ArgumentParser(
        description="Discover south nodes and groups, register ioc/... MQTT topics via Neuron API"
    )
    p.add_argument("--base-url", default="http://localhost:7001", help="Neuron API base")
    p.add_argument("--app", default="mqtt_hoanhbo", help="North MQTT app name")
    p.add_argument("--token", default="", help="Bearer JWT (skip login)")
    p.add_argument("--user", default="", help="Login name if no --token")
    p.add_argument(
        "--password",
        default=None,
        help="Login password (if omitted with --user, read from stdin)",
    )
    p.add_argument("--site", default=DEFAULT_SITE, help=f"Site segment (default {DEFAULT_SITE})")
    p.add_argument(
        "--data-type",
        default=DEFAULT_DATA_TYPE,
        help=f"Last path segment (default {DEFAULT_DATA_TYPE})",
    )
    p.add_argument("--batch-size", type=int, default=80, help="Groups per POST (default 80)")
    p.add_argument("--dry-run", action="store_true", help="List topics only, no subscribes")
    p.add_argument(
        "--plugin-filter",
        default="",
        help="Only drivers whose plugin name contains this substring (case-insensitive)",
    )
    p.add_argument(
        "--fail-on-module-overflow",
        action="store_true",
        help="Exit with error if more than 12 south drivers (after sort)",
    )
    args = p.parse_args()
    if args.user and args.password is None:
        args.password = sys.stdin.readline().rstrip("\n")
    return run(args)


if __name__ == "__main__":
    sys.exit(main())
