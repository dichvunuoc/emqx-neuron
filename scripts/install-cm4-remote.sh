#!/usr/bin/env bash
set -euo pipefail

# Backward-compatible entrypoint name.
# Docker flow was removed; this now forwards to native installer.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NATIVE_INSTALLER="${ROOT_DIR}/scripts/install-cm4-native-remote.sh"

if [[ ! -x "${NATIVE_INSTALLER}" ]]; then
  chmod +x "${NATIVE_INSTALLER}"
fi

echo "NOTE: Docker-based CM4 install was removed."
echo "Running native installer instead..."
"${NATIVE_INSTALLER}" "$@"
