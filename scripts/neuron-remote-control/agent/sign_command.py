#!/usr/bin/env python3
"""Sign a command envelope using HMAC-SHA256."""

from __future__ import annotations

import argparse
import hashlib
import hmac
import json
from pathlib import Path


def canonical_json(data):
    return json.dumps(data, sort_keys=True, separators=(",", ":"), ensure_ascii=True)


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate HMAC signature for a command envelope")
    parser.add_argument("--command", required=True, help="Path to command JSON")
    parser.add_argument("--secret", required=True, help="Shared HMAC secret")
    args = parser.parse_args()

    command = json.loads(Path(args.command).read_text(encoding="utf-8"))
    canonical = canonical_json(command)
    signature = hmac.new(
        args.secret.encode("utf-8"),
        canonical.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()
    print(signature)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
