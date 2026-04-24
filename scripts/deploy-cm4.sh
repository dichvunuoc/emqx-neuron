#!/usr/bin/env bash
set -euo pipefail

# Backward-compatible deploy script name.
# Docker deployment was removed; this now performs native build/deploy flow.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NATIVE_BUILDER="${ROOT_DIR}/scripts/build-native-cm4.sh"

if [[ ! -x "${NATIVE_BUILDER}" ]]; then
  chmod +x "${NATIVE_BUILDER}"
fi

echo "NOTE: Docker-based deploy was removed."
echo "Running native build/deploy..."
"${NATIVE_BUILDER}" "$@"
