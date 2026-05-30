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

- Bản **1 lệnh có hỏi tài khoản SSH** (host/user), phù hợp khi chưa setup alias:

```bash
chmod +x scripts/minipc-onecmd-install.sh
./scripts/minipc-onecmd-install.sh
```

Script sẽ:
- hỏi `host` + `username` nếu bạn chưa truyền qua `--ssh`;
- dùng sẵn `neuron-stack-cm4.tar` nếu có, thiếu thì tự build ARM64;
- nếu chưa có SSH key thì `scp/ssh` sẽ hiện prompt để bạn nhập mật khẩu.

- Cần **SSH bằng key** tới mini PC (`ssh-copy-id`), hoặc nhập mật khẩu khi `scp`/`ssh` hỏi.
- Đã build sẵn trên Mac: `BUILD=0` cùng `STACK_*`, hoặc `--no-build --tar ./neuron-stack-cm4.tar`.
- Chi tiết: [scripts/minipc-mac-ssh-deploy.sh](../../scripts/minipc-mac-ssh-deploy.sh).

## Gói bundle — cài lặp lại trên nhiều mini PC (USB / scp, có thể offline)

Trên **máy build** (Mac/CI), trong repo:

```bash
chmod +x scripts/minipc-bundle-pack.sh

# Build ARM64 + đóng gói compose + script + neuron-stack-*.tar vào dist/
STACK_REGISTRY=local/neuron STACK_TAG=cm4 \
PLATFORM=linux/arm64 NEURON_DOCKERFILE=Dockerfile.cm4 \
./scripts/minipc-bundle-pack.sh
```

- Kết quả: `dist/neuron-minipc-bundle-cm4/` gồm `docker-compose.yml`, `nginx.conf`, `.env.example`, `install-minipc-docker.sh`, `minipc-cm4-edge.sh`, `mqtt-fulltable-warmup.py`, `INSTALL.txt`, và `neuron-stack-cm4.tar` (hai image).
- Chỉ gói file cấu hình + script **không** build image: `INCLUDE_TAR=0 ./scripts/minipc-bundle-pack.sh` (tự chép file `.tar` vào thư mục bundle trước khi mang đi).
- Nén một file: `COMPRESS=1 ./scripts/minipc-bundle-pack.sh` → `dist/neuron-minipc-bundle-<tag>.tar.gz`.

Trên **mini PC**: copy cả thư mục (hoặc giải nén `.tar.gz`), làm theo `INSTALL.txt` — tóm tắt:

```bash
cd ~/neuron-minipc-bundle-cm4
export STACK_IMAGE_TAR="$PWD/neuron-stack-cm4.tar"   # nếu offline
export STACK_REGISTRY=local/neuron STACK_TAG=cm4
sudo -E bash ./install-minipc-docker.sh --bundle-dir "$PWD"
```

`--bundle-dir` / `MINIPC_BUNDLE_DIR` khiến installer **không** cần `curl` từ GitHub cho compose; nếu có `STACK_IMAGE_TAR` thì **bỏ qua** `docker pull` mặc định.

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

## Siemens S7 (Snap7)

Southbound plugins `libplugin-s7comm.so` and `libplugin-s7comm_for_300.so` require **libsnap7** in the Neuron image or on the host (`plugins/` directory). Build Snap7 for your CPU arch (see [Install-dependencies.md](../../Install-dependencies.md)), or disable with `cmake -DDISABLE_S7=ON`. On S7-1200/1500 enable PUT/GET and disable optimized block access in TIA Portal.

## Files

- [docker-compose.yml](./docker-compose.yml) — chạy production (chỉ `image:`, không build).
- [nginx.conf](./nginx.conf) — single-origin bridge for `/api/v2/remote/*`.
- [docker-compose.build.yml](./docker-compose.build.yml) — build cả hai image một lệnh.
- [.env.example](./.env.example) — image, port, token.
- [../../scripts/minipc-bundle-pack.sh](../../scripts/minipc-bundle-pack.sh) — đóng gói thư mục + tar cho nhiều máy.
- [../../scripts/mqtt-fulltable-warmup.py](../../scripts/mqtt-fulltable-warmup.py) — warm-up lại MQTT full-table snapshot.

## MQTT Full Table Warm-up

Nếu đã bật `Full Table On Change = true` nhưng payload trên mini PC vẫn thiếu tag:

```bash
# Trên mini PC (hoặc SSH): dùng bản copy trong thư mục bundle, hoặc đường dẫn repo
python3 mqtt-fulltable-warmup.py --base-url http://127.0.0.1 --mqtt-app <tên-app-mqtt>
```

Script sẽ:
- ép lại `full-table-on-change=true` cho app MQTT,
- restart app MQTT,
- restart toàn bộ south nodes,
- start lại MQTT để dựng snapshot mới.
