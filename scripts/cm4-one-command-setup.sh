#!/usr/bin/env bash
set -euo pipefail

# One-command CM4 setup (native only, no Docker).
#
# This wrapper forwards all args to install-cm4-native-remote.sh so existing
# operator habits keep working:
#   bash scripts/cm4-one-command-setup.sh --repo <git-url> --branch main --enable-service

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NATIVE_INSTALLER="${ROOT_DIR}/scripts/install-cm4-native-remote.sh"

if [[ ! -x "${NATIVE_INSTALLER}" ]]; then
  chmod +x "${NATIVE_INSTALLER}"
fi

echo "== Neuron CM4 one-command setup (native) =="
"${NATIVE_INSTALLER}" "$@"
