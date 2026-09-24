#!/usr/bin/env bash
# Build a versioned, checksummed Neuron Remote Edge bundle for repeatable mini-PC installs.
#
# ARM64/CM4 example:
#   STACK_REGISTRY=local/neuron STACK_TAG=remote-cm4 \
#   PLATFORM=linux/arm64 NEURON_DOCKERFILE=Dockerfile.cm4 COMPRESS=1 \
#   ./scripts/minipc-bundle-pack.sh
#
# Files-only bundle (no image build/tar):
#   INCLUDE_TAR=0 ./scripts/minipc-bundle-pack.sh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

# shellcheck source=scripts/minipc-resolve-stack-images.sh
source "${ROOT_DIR}/scripts/minipc-resolve-stack-images.sh"

STACK_TAG="${STACK_TAG:-latest}"
minipc_resolve_stack_images
NGINX_IMAGE="${NGINX_IMAGE:-nginx:1.27-alpine}"
BUNDLE_VERSION="${BUNDLE_VERSION:-$(tr -d '[:space:]' < "${ROOT_DIR}/version")}"
BUNDLE_COMMIT="${BUNDLE_COMMIT:-$(git -C "${ROOT_DIR}" rev-parse --short=12 HEAD 2>/dev/null || echo unknown)}"
if [[ -n "$(git -C "${ROOT_DIR}" status --porcelain --untracked-files=normal 2>/dev/null || true)" ]]; then
  BUNDLE_COMMIT="${BUNDLE_COMMIT}-dirty"
fi

SAFE_TAG="${STACK_TAG//\//-}"
DIST_ROOT="${DIST_ROOT:-${ROOT_DIR}/dist}"
OUTPUT_DIR="${OUTPUT_DIR:-${DIST_ROOT}/neuron-minipc-bundle-${SAFE_TAG}}"
INCLUDE_TAR="${INCLUDE_TAR:-1}"
COMPRESS="${COMPRESS:-0}"

validate_output_dir() {
  local dist_real
  local output_parent_real
  local output_name

  mkdir -p "${DIST_ROOT}"
  dist_real="$(cd "${DIST_ROOT}" && pwd -P)"
  output_parent_real="$(cd "$(dirname "${OUTPUT_DIR}")" && pwd -P)"
  output_name="$(basename "${OUTPUT_DIR}")"

  case "${output_name}" in
    neuron-minipc-bundle-*) ;;
    *)
      echo "ERROR: OUTPUT_DIR phải có tên neuron-minipc-bundle-*; từ chối xóa đường dẫn không an toàn: ${OUTPUT_DIR}" >&2
      exit 1
      ;;
  esac
  if [[ "${dist_real}" == "/" || "${dist_real}" == "${ROOT_DIR}" || "${output_parent_real}" != "${dist_real}" ]]; then
    echo "ERROR: OUTPUT_DIR phải là thư mục con trực tiếp, riêng biệt bên trong DIST_ROOT." >&2
    echo "DIST_ROOT=${dist_real}; OUTPUT_DIR=${OUTPUT_DIR}" >&2
    exit 1
  fi
}

require_file() {
  local file="$1"
  if [[ ! -f "${file}" ]]; then
    echo "ERROR: thiếu file ${file}" >&2
    exit 1
  fi
}

image_id() {
  local id
  id="$(docker image inspect --format '{{.Id}}' "$1" 2>/dev/null || true)"
  echo "${id:-unavailable}"
}

write_sha256s() {
  (
    cd "${OUTPUT_DIR}"
    find . -maxdepth 1 -type f ! -name SHA256SUMS -print | LC_ALL=C sort | while IFS= read -r file; do
      if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "${file}"
      else
        shasum -a 256 "${file}"
      fi
    done
  ) > "${OUTPUT_DIR}/SHA256SUMS"
}

write_archive_sha256() {
  local archive="$1"
  local archive_name
  archive_name="$(basename "${archive}")"
  (
    cd "$(dirname "${archive}")"
    if command -v sha256sum >/dev/null 2>&1; then
      sha256sum "${archive_name}" > "${archive_name}.sha256"
    else
      shasum -a 256 "${archive_name}" > "${archive_name}.sha256"
    fi
  )
}

require_file "${ROOT_DIR}/deploy/minipc/docker-compose.yml"
require_file "${ROOT_DIR}/deploy/minipc/nginx.conf"
require_file "${ROOT_DIR}/deploy/minipc/.env.example"
require_file "${ROOT_DIR}/deploy/minipc/HUONG-DAN-CAI-DAT-NEURON-REMOTE.md"
require_file "${ROOT_DIR}/scripts/install-minipc-docker.sh"
require_file "${ROOT_DIR}/scripts/mqtt-fulltable-warmup.py"

if [[ "${INCLUDE_TAR}" == "1" && -z "${PLATFORM:-}" ]]; then
  echo "ERROR: INCLUDE_TAR=1 yêu cầu PLATFORM=linux/amd64 hoặc PLATFORM=linux/arm64." >&2
  exit 1
fi

if [[ "${NEURON_IMAGE}" == "${REMOTE_STUB_IMAGE}" || \
      "${NEURON_IMAGE}" == "${NGINX_IMAGE}" || \
      "${REMOTE_STUB_IMAGE}" == "${NGINX_IMAGE}" ]]; then
  echo "ERROR: NEURON_IMAGE, REMOTE_STUB_IMAGE và NGINX_IMAGE phải là ba tag khác nhau." >&2
  exit 1
fi

validate_output_dir

echo ">> Bundle output: ${OUTPUT_DIR}"
rm -rf "${OUTPUT_DIR}"
mkdir -p "${OUTPUT_DIR}"

cp -a "${ROOT_DIR}/deploy/minipc/docker-compose.yml" "${OUTPUT_DIR}/"
cp -a "${ROOT_DIR}/deploy/minipc/nginx.conf" "${OUTPUT_DIR}/"
cp -a "${ROOT_DIR}/deploy/minipc/.env.example" "${OUTPUT_DIR}/"
sed \
  -e "s|^NEURON_IMAGE=.*|NEURON_IMAGE=${NEURON_IMAGE}|" \
  -e "s|^REMOTE_STUB_IMAGE=.*|REMOTE_STUB_IMAGE=${REMOTE_STUB_IMAGE}|" \
  -e "s|^NGINX_IMAGE=.*|NGINX_IMAGE=${NGINX_IMAGE}|" \
  "${OUTPUT_DIR}/.env.example" > "${OUTPUT_DIR}/.env.example.tmp"
mv "${OUTPUT_DIR}/.env.example.tmp" "${OUTPUT_DIR}/.env.example"
cp -a "${ROOT_DIR}/deploy/minipc/HUONG-DAN-CAI-DAT-NEURON-REMOTE.md" "${OUTPUT_DIR}/"
cp -a "${ROOT_DIR}/scripts/install-minipc-docker.sh" "${OUTPUT_DIR}/"
cp -a "${ROOT_DIR}/scripts/mqtt-fulltable-warmup.py" "${OUTPUT_DIR}/"
chmod +x "${OUTPUT_DIR}/install-minipc-docker.sh"

cat > "${OUTPUT_DIR}/install.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
BUNDLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "${BUNDLE_DIR}/install-minipc-docker.sh" --bundle-dir "${BUNDLE_DIR}" "$@"
EOF
chmod +x "${OUTPUT_DIR}/install.sh"

STACK_TAR_NAME="neuron-stack-${SAFE_TAG}.tar"
if [[ "${INCLUDE_TAR}" == "1" ]]; then
  export PUSH=0
  export EXPORT_STACK_TAR=1
  export OUTPUT_STACK_TAR="${OUTPUT_DIR}/${STACK_TAR_NAME}"
  export NEURON_IMAGE REMOTE_STUB_IMAGE NGINX_IMAGE
  export RELEASE_VERSION="${RELEASE_VERSION:-${BUNDLE_VERSION}}"
  export VCS_REF="${VCS_REF:-${BUNDLE_COMMIT}}"
  echo ">> Build + docker save → ${OUTPUT_STACK_TAR}"
  "${ROOT_DIR}/scripts/docker-release-build.sh"
else
  echo ">> INCLUDE_TAR=0 — không tạo ${STACK_TAR_NAME}."
fi

cat > "${OUTPUT_DIR}/BUNDLE-MANIFEST.txt" <<EOF
bundle_format=1
product=Neuron Remote Edge
version=${BUNDLE_VERSION}
source_revision=${BUNDLE_COMMIT}
platform=${PLATFORM:-native}
stack_tag=${STACK_TAG}
neuron_image=${NEURON_IMAGE}
neuron_image_id=$(image_id "${NEURON_IMAGE}")
remote_stub_image=${REMOTE_STUB_IMAGE}
remote_stub_image_id=$(image_id "${REMOTE_STUB_IMAGE}")
proxy_image=${NGINX_IMAGE}
proxy_image_id=$(image_id "${NGINX_IMAGE}")
contains_image_tar=${INCLUDE_TAR}
EOF

cat > "${OUTPUT_DIR}/INSTALL.txt" <<EOF
Neuron Remote Edge (Docker: Neuron + remote-stub + nginx proxy)
Version: ${BUNDLE_VERSION}; source: ${BUNDLE_COMMIT}; tag: ${SAFE_TAG}
Images: ${NEURON_IMAGE} / ${REMOTE_STUB_IMAGE} / ${NGINX_IMAGE}

--- Cài trên mini PC ---

1) Docker Engine + Docker Compose v2 phải có sẵn nếu máy hoàn toàn không có Internet.

2) Trong thư mục này chạy:

   sha256sum -c SHA256SUMS
   sudo ./install.sh

Installer tự nhận ${STACK_TAR_NAME}, nạp image, seed cấu hình và chờ healthcheck.

Sau cài:
  UI: http://<ip-mini-pc>/
  Remote API cùng origin: http://<ip-mini-pc>/api/v2/remote/connection
  Dữ liệu: /opt/neuron-minipc/data

Đặt REMOTE_NEURON_TOKEN trong /opt/neuron-minipc/.env, sau đó:
  cd /opt/neuron-minipc
  sudo docker compose up -d --force-recreate remote-stub

Hướng dẫn đầy đủ: HUONG-DAN-CAI-DAT-NEURON-REMOTE.md

Lưu ý: Remote Control hiện là skeleton/pilot, chưa phải bản production có mTLS/RBAC hoàn chỉnh.
EOF

write_sha256s
echo ">> INSTALL.txt, BUNDLE-MANIFEST.txt và SHA256SUMS đã ghi."

if [[ "${COMPRESS}" == "1" ]]; then
  ARCHIVE="${DIST_ROOT}/neuron-minipc-bundle-${SAFE_TAG}.tar.gz"
  echo ">> Nén → ${ARCHIVE}"
  ( cd "${DIST_ROOT}" && tar -czf "$(basename "${ARCHIVE}")" "$(basename "${OUTPUT_DIR}")" )
  write_archive_sha256 "${ARCHIVE}"
  echo ">> Xong. Tải ${ARCHIVE} và ${ARCHIVE}.sha256 lên mini PC."
else
  echo ">> Xong. Thư mục: ${OUTPUT_DIR}"
fi
