# Mini PC: Neuron + remote-control stub (Docker)

This layout runs **Neuron** (web UI baked from [neuron-dashboard](../../neuron-dashboard) in your images) and the **FastAPI backend stub** for [remote control APIs](../../scripts/neuron-remote-control/backend-stub).
An internal Nginx proxy exposes a single origin on port `80`: `/api/v2/remote/*` goes to stub, everything else goes to Neuron.

Runtime vẫn là **hai container** (Neuron C++ và stub Python khác base image), nhưng **một phiên bản chung** `STACK_TAG` và **một lệnh build** (hoặc một file `docker save` gồm cả hai).

## Mac → mini PC qua SSH (một lệnh)

Trên **Mac** (Docker Desktop bật), từ thư mục repo:

```bash
chmod +x scripts/minipc-mac-ssh-deploy.sh

# Build ARM64 + scp tar + ssh: cài Docker (nếu cần), docker load, compose up
STACK_REGISTRY=local/neuron STACK_TAG=cm4 \
PLATFORM=linux/arm64 NEURON_DOCKERFILE=Dockerfile.cm4 \
./scripts/minipc-mac-ssh-deploy.sh --ssh pi@192.168.1.50
```

- Cần **SSH bằng key** tới mini PC (`ssh-copy-id`), hoặc nhập mật khẩu khi `scp`/`ssh` hỏi.
- Đã build sẵn trên Mac: `BUILD=0` cùng `STACK_*`, hoặc `--no-build --tar ./neuron-stack-cm4.tar`.
- Chi tiết: [scripts/minipc-mac-ssh-deploy.sh](../../scripts/minipc-mac-ssh-deploy.sh).

## 1) Build và push (máy dev / CI) — một lệnh

Registry + tag chung:

```bash
chmod +x scripts/docker-release-build.sh

# x86_64
PUSH=1 STACK_REGISTRY=registry.example.com/iot STACK_TAG=1.0 ./scripts/docker-release-build.sh
# → neuron-full:1.0 và neuron-remote-stub:1.0
```

ARM64 (CM4):

```bash
PUSH=1 PLATFORM=linux/arm64 NEURON_DOCKERFILE=Dockerfile.cm4 \
  STACK_REGISTRY=registry.example.com/iot STACK_TAG=1.0-arm64 ./scripts/docker-release-build.sh
```

**Một file tar offline** (hai image trong cùng file):

```bash
EXPORT_STACK_TAR=1 STACK_REGISTRY=registry.example.com/iot STACK_TAG=1.0 \
  PLATFORM=linux/arm64 NEURON_DOCKERFILE=Dockerfile.cm4 ./scripts/docker-release-build.sh
# → neuron-stack-1.0.tar — trên CM4: export STACK_IMAGE_TAR=... khi chạy install
```

**Chỉ build local** (không push): bỏ `PUSH=1`.

**Docker Compose build** (không dùng script):

```bash
cd deploy/minipc
cp .env.example .env
# Sửa NEURON_IMAGE + REMOTE_STUB_IMAGE (cùng tag). CM4: thêm NEURON_DOCKERFILE=Dockerfile.cm4
docker compose -f docker-compose.build.yml --env-file .env build
```

Xem [docker-compose.build.yml](./docker-compose.build.yml).

## 2) Cài trên mini PC (curl)

```bash
export INSTALL_SCRIPT_REPO=your-org/your-fork
export INSTALL_SCRIPT_BRANCH=main
export STACK_REGISTRY=registry.example.com/iot
export STACK_TAG=1.0

curl -fsSL "https://raw.githubusercontent.com/${INSTALL_SCRIPT_REPO}/${INSTALL_SCRIPT_BRANCH}/scripts/install-minipc-docker.sh" | bash -s --
```

Hoặc truyền rõ: `bash -s -- --neuron-image ... --stub-image ...`

Offline: `STACK_IMAGE_TAR=/path/neuron-stack-1.0.tar` (sau `EXPORT_STACK_TAR=1`).

Sau khi cài, đặt `REMOTE_NEURON_TOKEN` trong `/opt/neuron-minipc/.env`.

## CM4: một file trên máy (SSH)

```bash
curl -fsSL -o minipc-cm4-edge.sh "https://raw.githubusercontent.com/your-org/your-repo/main/scripts/minipc-cm4-edge.sh"
chmod +x minipc-cm4-edge.sh

export INSTALL_SCRIPT_REPO=your-org/your-repo
export INSTALL_SCRIPT_BRANCH=main
export STACK_REGISTRY=your-registry/iot
export STACK_TAG=1.0-arm64
sudo ./minipc-cm4-edge.sh install
```

**Cập nhật:** `sudo ./minipc-cm4-edge.sh update` (sửa `.env` nếu đổi tag).

## Files

- [docker-compose.yml](./docker-compose.yml) — chạy production (chỉ `image:`, không build).
- [nginx.conf](./nginx.conf) — single-origin bridge for `/api/v2/remote/*`.
- [docker-compose.build.yml](./docker-compose.build.yml) — build cả hai image một lệnh.
- [.env.example](./.env.example) — image, port, token.
- [../../scripts/mqtt-fulltable-warmup.py](../../scripts/mqtt-fulltable-warmup.py) — warm-up lại MQTT full-table snapshot.

## MQTT Full Table Warm-up

Nếu đã bật `Full Table On Change = true` nhưng payload trên mini PC vẫn thiếu tag:

```bash
ssh minipc-hoanhbo 'python3 /opt/neuron/emqx-neuron/scripts/mqtt-fulltable-warmup.py --base-url http://127.0.0.1 --mqtt-app mqtt-hoanhbo'
```

Script sẽ:
- ép lại `full-table-on-change=true` cho app MQTT,
- restart app MQTT,
- restart toàn bộ south nodes,
- start lại MQTT để dựng snapshot mới.
