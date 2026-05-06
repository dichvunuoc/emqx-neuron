# Mini PC: Neuron + remote-control stub (Docker)

This layout runs **Neuron** (web UI baked from [neuron-dashboard](../../neuron-dashboard) in your images) and the **FastAPI backend stub** for [remote control APIs](../../scripts/neuron-remote-control/backend-stub) on ports **7000** and **18080**.

## 1) Build and push images (developer machine or CI)

From the repository root:

```bash
chmod +x scripts/docker-release-build.sh

# x86_64 Neuron (default Dockerfile) + stub
NEURON_IMAGE=registry.example.com/iot/neuron-full:1.0 \
STUB_IMAGE=registry.example.com/iot/neuron-remote-stub:1.0 \
PUSH=1 ./scripts/docker-release-build.sh
```

ARM64 Neuron ([Dockerfile.cm4](../../Dockerfile.cm4)) plus stub (multi-arch if your registry supports it):

```bash
PLATFORM=linux/arm64 NEURON_DOCKERFILE=Dockerfile.cm4 \
NEURON_IMAGE=registry.example.com/iot/neuron-full:1.0-arm64 \
STUB_IMAGE=registry.example.com/iot/neuron-remote-stub:1.0-arm64 \
PUSH=1 ./scripts/docker-release-build.sh
```

You can also build the ARM Neuron image alone with [scripts/build-arm64-image.sh](../../scripts/build-arm64-image.sh).

## 2) Install on each mini PC (one command)

Set your GitHub `owner/repo` and branch, and your registry tags:

```bash
export INSTALL_SCRIPT_REPO=your-org/your-fork
export INSTALL_SCRIPT_BRANCH=main

curl -fsSL "https://raw.githubusercontent.com/${INSTALL_SCRIPT_REPO}/${INSTALL_SCRIPT_BRANCH}/scripts/install-minipc-docker.sh" | \
  bash -s -- \
    --neuron-image registry.example.com/iot/neuron-full:1.0 \
    --stub-image registry.example.com/iot/neuron-remote-stub:1.0
```

Optional: `IMAGE_TAR` / `STUB_IMAGE_TAR` with `docker load` before pull (offline), or `--source-base-url` if you host the compose files elsewhere.

After install, set `REMOTE_NEURON_TOKEN` in `/opt/neuron-minipc/.env` to a valid Neuron JWT for API calls from the stub.

## Files

- [docker-compose.yml](./docker-compose.yml) — two services, **no** `./data/dist` bind-mount (empty dir would hide the UI in the image).
- [.env.example](./.env.example) — copy to `.env` and adjust images, ports, token.
