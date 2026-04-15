# Neuron on CM4 (Docker)

This guide targets Raspberry Pi CM4-class devices (4GB RAM / 32GB eMMC).

## 0a) One-liner install (no git clone) — like `curl | bash`

You do **not** need to copy the full source tree. The installer downloads `docker-compose.yml` and `.env.example` from GitHub (raw), installs Docker if needed, pulls an image, and starts Neuron.

**Recommended:** pass the public Docker Hub image (ARM64 supported):

```bash
curl -fsSL https://raw.githubusercontent.com/emqx/neuron/main/scripts/install-cm4-remote.sh | bash -s -- --image emqx/neuron:latest
```

Or use the convenience flag (same result):

```bash
curl -fsSL https://raw.githubusercontent.com/emqx/neuron/main/scripts/install-cm4-remote.sh | bash -s -- --public-image
```

**Custom registry** (image you built and pushed elsewhere):

```bash
curl -fsSL https://raw.githubusercontent.com/emqx/neuron/main/scripts/install-cm4-remote.sh | bash -s -- --image registry.example.com/iot/neuron:cm4
```

**If `deploy/cm4` (or the installer script) only exists on your fork**, point both the script URL and `--source-base` at that fork:

```bash
curl -fsSL https://raw.githubusercontent.com/YOUR_USER/YOUR_FORK/main/scripts/install-cm4-remote.sh | bash -s -- \
  --source-base https://raw.githubusercontent.com/YOUR_USER/YOUR_FORK/main/deploy/cm4/ \
  --image emqx/neuron:latest
```

You can also set only the compose base via env:

```bash
SOURCE_BASE_URL=https://raw.githubusercontent.com/YOUR_USER/YOUR_FORK/main/deploy/cm4/ \
curl -fsSL https://raw.githubusercontent.com/emqx/neuron/main/scripts/install-cm4-remote.sh | bash -s -- --image emqx/neuron:latest
```

Install directory defaults to `/opt/neuron-cm4`. Override with `INSTALL_DIR=/path` or `--install-dir /path`.

**Offline image (tar on the device):**

```bash
IMAGE_TAR=/tmp/neuron-cm4-image.tar \
curl -fsSL https://raw.githubusercontent.com/emqx/neuron/main/scripts/install-cm4-remote.sh | bash -s -- --image neuron:cm4
```

(`--image` must match the tag loaded from the tar.)

## 0b) One-command setup from a cloned repo

From repository root on CM4:

```bash
chmod +x scripts/cm4-one-command-setup.sh
scripts/cm4-one-command-setup.sh
```

This single command flow will:
- install Docker and Docker Compose plugin (if missing),
- enable/start Docker service,
- create `deploy/cm4/data/*` runtime folders,
- create `deploy/cm4/.env` from template if missing,
- pull image from `.env` (`NEURON_IMAGE`) or load from tar if `IMAGE_TAR` is set,
- start Neuron container and run a basic smoke check.

If deploying from image tar:

```bash
IMAGE_TAR=/tmp/neuron-cm4-image.tar scripts/cm4-one-command-setup.sh
```

## 1) Build ARM64 image on a stronger host

From repository root:

```bash
chmod +x scripts/build-arm64-image.sh scripts/deploy-cm4.sh scripts/cm4-one-command-setup.sh
```

### Option A: push to registry

```bash
IMAGE_NAME=registry.example.com/iot/neuron:cm4-latest PUSH_IMAGE=1 scripts/build-arm64-image.sh
```

### Option B: export tar and copy to CM4

```bash
IMAGE_NAME=neuron:cm4 EXPORT_TAR=1 OUTPUT_TAR=neuron-cm4-image.tar scripts/build-arm64-image.sh
scp neuron-cm4-image.tar <cm4-user>@<cm4-ip>:/tmp/
```

## 2) Prepare CM4 runtime layout

On CM4:

```bash
cd /opt/neuron
git clone <your-neuron-repo> neuron-src
cd neuron-src
cp deploy/cm4/.env.example deploy/cm4/.env
mkdir -p deploy/cm4/data/{config,logs,persistence,dist}
```

Adjust `deploy/cm4/.env` for your image/tag and timezone.

## 3) Deploy on CM4

If using image tar:

```bash
IMAGE_TAR=/tmp/neuron-cm4-image.tar scripts/deploy-cm4.sh
```

If pulling from registry:

```bash
scripts/deploy-cm4.sh
```

The service runs with `restart: unless-stopped`.

## 4) Smoke test checklist

```bash
cd deploy/cm4
docker compose --env-file .env ps
docker compose --env-file .env logs --tail=200 neuron
curl -fsS http://127.0.0.1:7000 >/dev/null && echo "UI/API reachable"
```

Validation points:
- Container state is `running` and healthcheck turns `healthy`.
- Web UI/API accessible on `${NEURON_HTTP_PORT}` (default 7000).
- Startup logs show default plugins loading without crash loops.

## 5) CM4 low-resource tuning recommendations

- Prefer remote build host and deploy image only to CM4.
- Keep Docker JSON logs capped (`max-size=10m`, `max-file=3` is preconfigured).
- Monitor memory and disk regularly:
  ```bash
  free -h
  df -h
  docker stats --no-stream
  ```
- If memory pressure appears:
  - reduce active drivers/plugins to only required ones,
  - lower polling rate or node count in plugin configs,
  - keep only one Neuron container on CM4.
- Reclaim eMMC periodically:
  ```bash
  docker image prune -f
  docker container prune -f
  docker volume ls
  ```

## 6) Optional systemd wrapper for auto-start

If Docker daemon is already enabled at boot, `restart: unless-stopped` is enough.
If needed, add a one-shot systemd unit that runs:

```bash
docker compose --env-file /opt/neuron/neuron-src/deploy/cm4/.env -f /opt/neuron/neuron-src/deploy/cm4/docker-compose.yml up -d
```
