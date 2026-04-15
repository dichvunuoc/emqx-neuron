#!/usr/bin/env bash
# Build and open a shell in the ARM64 CM4 simulator (Docker-in-Docker).
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}/deploy/cm4"
docker compose -f docker-compose.cm4-sim.yml build
exec docker compose -f docker-compose.cm4-sim.yml run --rm --service-ports cm4-sim bash "$@"
