#!/usr/bin/env bash
set -euo pipefail

# Legacy name kept for compatibility; this now runs native flow.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-build-native-cm4}"

echo "NOTE: Docker OPC UA E2E flow was removed."
echo "Running native build + OPC UA E2E test..."

"${ROOT_DIR}/scripts/build-native-cm4.sh"

if [[ ! -x "${ROOT_DIR}/${BUILD_DIR}/neuron" ]]; then
  echo "ERROR: ${ROOT_DIR}/${BUILD_DIR}/neuron not found" >&2
  exit 1
fi

(
  cd "${ROOT_DIR}/${BUILD_DIR}"
  LD_LIBRARY_PATH="/usr/local/lib:${LD_LIBRARY_PATH:-}" ./neuron --log &
  NPID=$!
  trap 'kill "${NPID}" 2>/dev/null || true' EXIT
  sleep 10
  cd "${ROOT_DIR}/tests/ft"
  OPCUA_E2E=1 python3 -m pytest driver/test_opcua_plugin.py::TestOpcUaPluginE2e -v --tb=short
)
