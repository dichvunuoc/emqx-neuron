#!/usr/bin/env bash
# Đóng gói một thư mục (hoặc file .tar.gz) để cài Neuron stack lên nhiều mini PC:
#   compose + nginx + .env.example + script cài đặt + (tuỳ chọn) neuron-stack-*.tar
#
# Chạy trên máy build (Mac/CI), trong repo:
#
#   chmod +x scripts/minipc-bundle-pack.sh
#   STACK_REGISTRY=local/neuron STACK_TAG=cm4 \
#   PLATFORM=linux/arm64 NEURON_DOCKERFILE=Dockerfile.cm4 \
#   ./scripts/minipc-bundle-pack.sh
#
#   → dist/neuron-minipc-bundle-cm4/  (và neuron-stack-cm4.tar nếu INCLUDE_TAR=1)
#
# Gói không build (chỉ file cấu hình + script, image đã có sẵn tar khác):
#   INCLUDE_TAR=0 ./scripts/minipc-bundle-pack.sh
#
# Xuất thêm .tar.gz của cả thư mục bundle:
#   COMPRESS=1 ./scripts/minipc-bundle-pack.sh
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

# shellcheck source=scripts/minipc-resolve-stack-images.sh
source "${ROOT_DIR}/scripts/minipc-resolve-stack-images.sh"

STACK_TAG="${STACK_TAG:-latest}"
minipc_resolve_stack_images

SAFE_TAG="${STACK_TAG//\//-}"
DIST_ROOT="${DIST_ROOT:-${ROOT_DIR}/dist}"
OUTPUT_DIR="${OUTPUT_DIR:-${DIST_ROOT}/neuron-minipc-bundle-${SAFE_TAG}}"
INCLUDE_TAR="${INCLUDE_TAR:-1}"
COMPRESS="${COMPRESS:-0}"

require_file() {
  local f="$1"
  if [[ ! -f "${f}" ]]; then
    echo "ERROR: thiếu file ${f}" >&2
    exit 1
  fi
}

require_file "${ROOT_DIR}/deploy/minipc/docker-compose.yml"
require_file "${ROOT_DIR}/deploy/minipc/nginx.conf"
require_file "${ROOT_DIR}/deploy/minipc/.env.example"
require_file "${ROOT_DIR}/scripts/install-minipc-docker.sh"
require_file "${ROOT_DIR}/scripts/minipc-cm4-edge.sh"
require_file "${ROOT_DIR}/scripts/mqtt-fulltable-warmup.py"

echo ">> Bundle output: ${OUTPUT_DIR}"
rm -rf "${OUTPUT_DIR}"
mkdir -p "${OUTPUT_DIR}"

cp -a "${ROOT_DIR}/deploy/minipc/docker-compose.yml" "${OUTPUT_DIR}/"
cp -a "${ROOT_DIR}/deploy/minipc/nginx.conf" "${OUTPUT_DIR}/"
cp -a "${ROOT_DIR}/deploy/minipc/.env.example" "${OUTPUT_DIR}/"
cp -a "${ROOT_DIR}/scripts/install-minipc-docker.sh" "${OUTPUT_DIR}/"
cp -a "${ROOT_DIR}/scripts/minipc-cm4-edge.sh" "${OUTPUT_DIR}/"
cp -a "${ROOT_DIR}/scripts/mqtt-fulltable-warmup.py" "${OUTPUT_DIR}/"
chmod +x "${OUTPUT_DIR}/install-minipc-docker.sh" "${OUTPUT_DIR}/minipc-cm4-edge.sh"

STACK_TAR_NAME="neuron-stack-${SAFE_TAG}.tar"
if [[ "${INCLUDE_TAR}" == "1" ]]; then
  if [[ -z "${NEURON_IMAGE:-}" || -z "${REMOTE_STUB_IMAGE:-}" ]]; then
    echo "ERROR: đặt STACK_REGISTRY (+ STACK_TAG) hoặc NEURON_IMAGE + REMOTE_STUB_IMAGE để build/save image." >&2
    exit 1
  fi
  export PUSH=0
  export EXPORT_STACK_TAR=1
  export OUTPUT_STACK_TAR="${OUTPUT_DIR}/${STACK_TAR_NAME}"
  export NEURON_IMAGE
  export REMOTE_STUB_IMAGE
  echo ">> Build + docker save → ${OUTPUT_STACK_TAR}"
  "${ROOT_DIR}/scripts/docker-release-build.sh"
else
  echo ">> INCLUDE_TAR=0 — không tạo ${STACK_TAR_NAME} (chép sẵn tar vào ${OUTPUT_DIR} nếu cần)."
fi

OFFLINE_TAR_HINT=""
if [[ "${INCLUDE_TAR}" == "1" ]]; then
  OFFLINE_TAR_HINT="export STACK_IMAGE_TAR=\"\$PWD/${STACK_TAR_NAME}\""
else
  OFFLINE_TAR_HINT="# export STACK_IMAGE_TAR=\"\$PWD/neuron-stack-${SAFE_TAG}.tar\"  # đặt file tar từ docker save vào đây trước"
fi

REG_HINT="${STACK_REGISTRY:-your-registry/iot}"

cat > "${OUTPUT_DIR}/INSTALL.txt" <<EOF
Neuron mini PC bundle (Docker: Neuron + remote-stub + nginx proxy)
Tag: ${SAFE_TAG}
Images (khớp sau khi load): ${NEURON_IMAGE} / ${REMOTE_STUB_IMAGE}

--- Trên mini PC (scp/usb cả thư mục này, ví dụ ~/neuron-minipc-bundle-${SAFE_TAG}) ---

1) Offline — load image từ tar rồi cài (không cần registry):

   cd "\$(dirname "\$0")"
   ${OFFLINE_TAR_HINT}
   export STACK_REGISTRY=${REG_HINT} STACK_TAG=${STACK_TAG}
   sudo -E bash ./install-minipc-docker.sh --bundle-dir "\$PWD"

   NEURON_IMAGE trong .env phải trùng tên image sau khi docker load (thường là .../neuron-full:${STACK_TAG}).

2) Online — mini PC có Internet, kéo image từ registry:

   sudo bash ./install-minipc-docker.sh --bundle-dir "\$PWD" \\
     --neuron-image YOUR/neuron-full:TAG --stub-image YOUR/neuron-remote-stub:TAG

3) Cùng nội dung bằng minipc-cm4-edge.sh:

   export MINIPC_BUNDLE_DIR="\$PWD"
   ${OFFLINE_TAR_HINT}
   export STACK_REGISTRY=${REG_HINT} STACK_TAG=${STACK_TAG}
   sudo -E bash ./minipc-cm4-edge.sh install

Sau cài: UI http://<ip>/ (port 80 mặc định). Stub: http://<ip>:18080/docs
Cấu hình trống: nếu Neuron báo thiếu neuron.json, chạy một lần:
  sudo docker cp neuron-minipc:/opt/neuron/config/neuron.json /opt/neuron-minipc/data/config/

Đặt REMOTE_NEURON_TOKEN trong /opt/neuron-minipc/.env sau khi tạo token trong Neuron.

MQTT full-table warm-up (nếu cần):
  python3 mqtt-fulltable-warmup.py --base-url http://127.0.0.1 --mqtt-app <tên-app>
EOF

echo ">> INSTALL.txt đã ghi."

if [[ "${COMPRESS}" == "1" ]]; then
  ARCHIVE="${DIST_ROOT}/neuron-minipc-bundle-${SAFE_TAG}.tar.gz"
  echo ">> Nén → ${ARCHIVE}"
  ( cd "${DIST_ROOT}" && tar -czf "neuron-minipc-bundle-${SAFE_TAG}.tar.gz" "neuron-minipc-bundle-${SAFE_TAG}" )
  echo ">> Xong. Tải ${ARCHIVE} lên mini PC, giải nén rồi làm theo INSTALL.txt"
else
  echo ">> Xong. Thư mục: ${OUTPUT_DIR}"
fi
