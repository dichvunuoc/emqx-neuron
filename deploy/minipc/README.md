# Mini PC: Neuron + remote-control stub (Docker)

This layout runs **Neuron** (web UI baked from [neuron-dashboard](../../neuron-dashboard) in your images) and the **FastAPI backend stub** for [remote control APIs](../../scripts/neuron-remote-control/backend-stub).
An internal Nginx proxy exposes a single origin on port `80`: `/api/v2/remote/*` goes to stub, everything else goes to Neuron.

Runtime gồm **ba container**: Neuron C++, remote stub Python và Nginx edge proxy. Hai image ứng dụng dùng chung `STACK_TAG`; bundle offline chứa đủ cả ba image, không cần pull Nginx khi cài.

Đây là stack pilot, không phải cấu hình production: remote API chưa có auth/RBAC độc lập và bundle không chứa control server phía trung tâm.

Hướng dẫn cài đặt dành cho người vận hành: [HUONG-DAN-CAI-DAT-NEURON-REMOTE.md](./HUONG-DAN-CAI-DAT-NEURON-REMOTE.md).

## Gói bundle — cài lặp lại trên nhiều mini PC (USB / scp, có thể offline)

Trên **máy build** (Mac/CI), trong repo:

```bash
chmod +x scripts/minipc-bundle-pack.sh

# Build ARM64 + đóng gói compose + script + neuron-stack-*.tar vào dist/
STACK_REGISTRY=local/neuron STACK_TAG=cm4 \
PLATFORM=linux/arm64 NEURON_DOCKERFILE=Dockerfile.cm4 \
./scripts/minipc-bundle-pack.sh
```

- Kết quả: `dist/neuron-minipc-bundle-cm4/` gồm cấu hình Compose, `install.sh`, hướng dẫn tiếng Việt, manifest phiên bản, `SHA256SUMS`, và `neuron-stack-cm4.tar` (đủ ba image).
- Chỉ gói file cấu hình + script **không** build image: `INCLUDE_TAR=0 ./scripts/minipc-bundle-pack.sh`. Chế độ này không phải bundle offline hoàn chỉnh; không chép thêm tar chưa được ghi vào `SHA256SUMS`.
- Nén một file: `COMPRESS=1 ./scripts/minipc-bundle-pack.sh` → `dist/neuron-minipc-bundle-<tag>.tar.gz`.

Trên **mini PC**: copy cả thư mục (hoặc giải nén `.tar.gz`), làm theo `INSTALL.txt` — tóm tắt:

```bash
cd ~/neuron-minipc-bundle-cm4
sha256sum -c SHA256SUMS
sudo ./install.sh
```

Installer tự nhận file `neuron-stack-*.tar`, kiểm tra kiến trúc, seed đầy đủ cấu hình ban đầu và chờ ba healthcheck. `--bundle-dir` khiến installer không cần tải compose từ GitHub.

## 1) Build và push (máy dev / CI) — một lệnh

Registry + tag chung:

```bash
chmod +x scripts/docker-release-build.sh

# x86_64
PUSH=1 PLATFORM=linux/amd64 \
  STACK_REGISTRY=registry.example.com/iot STACK_TAG=1.0 ./scripts/docker-release-build.sh
# → neuron-full:1.0 và neuron-remote-stub:1.0
```

ARM64 (CM4):

```bash
PUSH=1 PLATFORM=linux/arm64 NEURON_DOCKERFILE=Dockerfile.cm4 \
  STACK_REGISTRY=registry.example.com/iot STACK_TAG=1.0-arm64 ./scripts/docker-release-build.sh
```

**Một file tar offline** (Neuron, remote stub và Nginx trong cùng file):

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

## Siemens S7 (Snap7)

Southbound plugins `libplugin-s7comm.so` and `libplugin-s7comm_for_300.so` require **libsnap7** in the Neuron image or on the host (`plugins/` directory). Build Snap7 for your CPU arch (see [Install-dependencies.md](../../Install-dependencies.md)), or disable with `cmake -DDISABLE_S7=ON`. On S7-1200/1500 enable PUT/GET and disable optimized block access in TIA Portal.

## Files

- [docker-compose.yml](./docker-compose.yml) — cấu hình runtime (chỉ `image:`, không build).
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
