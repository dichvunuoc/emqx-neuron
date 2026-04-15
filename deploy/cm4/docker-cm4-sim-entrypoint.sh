#!/usr/bin/env bash
# Start dockerd inside the simulator (no systemd). Then run CMD.
set -euo pipefail

if docker info >/dev/null 2>&1; then
  exec "$@"
fi

echo ">> [cm4-sim] Starting dockerd (nested Docker, storage-driver=vfs)..."
# vfs is reliable for Docker-in-Docker; slower but avoids overlay-on-overlay issues.
dockerd --storage-driver=vfs --host=unix:///var/run/docker.sock >/tmp/dockerd.log 2>&1 &
for _ in $(seq 1 90); do
  if docker info >/dev/null 2>&1; then
    echo ">> [cm4-sim] dockerd is ready"
    exec "$@"
  fi
  sleep 1
done

echo "ERROR: dockerd did not become ready. Last log:" >&2
tail -80 /tmp/dockerd.log >&2 || true
exit 1
