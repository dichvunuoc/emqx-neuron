from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Optional


class ConnectionStore:
    def __init__(self, path: Path) -> None:
        self.path = path
        self.secret_path = path.with_suffix(".secret")
        self.path.parent.mkdir(parents=True, exist_ok=True)

    def load(self) -> Optional[Dict[str, Any]]:
        if not self.path.exists():
            return None
        return json.loads(self.path.read_text(encoding="utf-8"))

    def save(self, profile: Dict[str, Any]) -> Dict[str, Any]:
        now = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
        profile = dict(profile)
        profile["updatedAt"] = now
        self.path.write_text(json.dumps(profile, ensure_ascii=True, indent=2), encoding="utf-8")
        return profile

    def save_hmac_secret(self, secret: str) -> None:
        # Stub storage only; production should use OS keychain/keystore.
        self.secret_path.write_text(secret, encoding="utf-8")

    def load_hmac_secret(self) -> str:
        if not self.secret_path.exists():
            return ""
        return self.secret_path.read_text(encoding="utf-8").strip()
