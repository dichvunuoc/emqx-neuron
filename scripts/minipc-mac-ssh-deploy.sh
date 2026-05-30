#!/usr/bin/env bash
# Chạy trên Mac: build (tuỳ chọn) → docker save → scp sang mini PC → ssh cài Docker + load + compose up.
#
# Yêu cầu: ssh/scp không cần mật khẩu (key đã ssh-copy-id), hoặc bạn nhập mật khẩu khi script hỏi.
# Mini PC: Debian/Ubuntu kiểu Raspberry Pi OS.
#
# Ví dụ CM4 (build ARM64 trên Mac, đẩy xuống pi@IP):
#   chmod +x scripts/minipc-mac-ssh-deploy.sh
#   STACK_REGISTRY=local/neuron STACK_TAG=cm4 \
#   PLATFORM=linux/arm64 NEURON_DOCKERFILE=Dockerfile.cm4 \
#   ./scripts/minipc-mac-ssh-deploy.sh --ssh pi@192.168.1.50
#
# Đã build sẵn hai image trên Mac (đúng tag), chỉ đóng gói + đẩy:
#   BUILD=0 STACK_REGISTRY=local/neuron STACK_TAG=cm4 \
#   ./scripts/minipc-mac-ssh-deploy.sh --ssh pi@192.168.1.50
#
# Dùng sẵn file tar:
#   ./scripts/minipc-mac-ssh-deploy.sh --ssh pi@cm4 --no-build --tar ./neuron-stack-cm4.tar \
#     --stack-registry local/neuron --stack-tag cm4
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/minipc-resolve-stack-images.sh
source "${ROOT_DIR}/scripts/minipc-resolve-stack-images.sh"

MINIPC_SSH="${MINIPC_SSH:-}"
INSTALL_DIR="${INSTALL_DIR:-/opt/neuron-minipc}"
BUILD="${BUILD:-1}"
STACK_TAR_LOCAL="${STACK_TAR_LOCAL:-}"
NEURON_HTTP_PORT="${NEURON_HTTP_PORT:-80}"
REMOTE_STUB_HTTP_PORT="${REMOTE_STUB_HTTP_PORT:-18080}"
SKIP_DOCKER_ON_REMOTE="${SKIP_DOCKER_ON_REMOTE:-0}"
REMOVE_REMOTE_TAR_AFTER="${REMOVE_REMOTE_TAR_AFTER:-1}"

usage() {
  cat <<'HELP'
minipc-mac-ssh-deploy.sh — Mac: build/scp/ssh cài stack Neuron + stub trên mini PC

Bắt buộc:
  --ssh user@host

Tuỳ chọn:
  --install-dir PATH     trên mini PC (mặc định /opt/neuron-minipc)
  --no-build             không build; dùng image đã có hoặc --tar
  --tar PATH             dùng file tar có sẵn (bỏ qua build và docker save)

Env (trước khi gọi script):
  STACK_REGISTRY + STACK_TAG     tên image: .../neuron-full:TAG và .../neuron-remote-stub:TAG
  NEURON_IMAGE + REMOTE_STUB_IMAGE   (nếu không dùng STACK_*)
  BUILD=0                        chỉ đóng gói + deploy
  PLATFORM, NEURON_DOCKERFILE    khi build CM4: linux/arm64 + Dockerfile.cm4
  NEURON_HTTP_PORT, REMOTE_STUB_HTTP_PORT
  SKIP_DOCKER_ON_REMOTE=1        chỉ khi **không** muốn cài Docker tự động (lỗi nếu máy chưa có docker)
HELP
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ssh)
      MINIPC_SSH="${2:-}"
      shift 2
      ;;
    --install-dir)
      INSTALL_DIR="${2:-}"
      shift 2
      ;;
    --no-build)
      BUILD=0
      shift
      ;;
    --tar)
      STACK_TAR_LOCAL="${2:-}"
      BUILD=0
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Không rõ: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "${MINIPC_SSH}" ]]; then
  echo "ERROR: thiếu --ssh user@host" >&2
  usage
  exit 1
fi

STACK_TAG="${STACK_TAG:-latest}"
minipc_resolve_stack_images

if [[ -z "${NEURON_IMAGE}" || -z "${REMOTE_STUB_IMAGE}" ]]; then
  echo "ERROR: đặt STACK_REGISTRY (+ STACK_TAG) hoặc NEURON_IMAGE + REMOTE_STUB_IMAGE." >&2
  exit 1
fi

SAFE_TAG="${STACK_TAG//\//-}"
STACK_TAR=""
CLEANUP_LOCAL_TAR=""

if [[ "${BUILD}" == "1" ]]; then
  export PUSH=0
  export EXPORT_STACK_TAR=1
  export OUTPUT_STACK_TAR="${ROOT_DIR}/neuron-stack-${SAFE_TAG}.tar"
  export NEURON_IMAGE
  export REMOTE_STUB_IMAGE
  echo ">> Build trên Mac + xuất tar → ${OUTPUT_STACK_TAR}"
  "${ROOT_DIR}/scripts/docker-release-build.sh"
  STACK_TAR="${OUTPUT_STACK_TAR}"
elif [[ -n "${STACK_TAR_LOCAL}" ]]; then
  STACK_TAR="${STACK_TAR_LOCAL}"
  if [[ ! -f "${STACK_TAR}" ]]; then
    echo "ERROR: không thấy ${STACK_TAR}" >&2
    exit 1
  fi
else
  STACK_TAR="/tmp/neuron-mac-deploy-$$.tar"
  CLEANUP_LOCAL_TAR="${STACK_TAR}"
  echo ">> docker save → ${STACK_TAR}"
  docker save -o "${STACK_TAR}" "${NEURON_IMAGE}" "${REMOTE_STUB_IMAGE}"
fi

ENV_TMP="$(mktemp)"
{
  echo "NEURON_IMAGE=${NEURON_IMAGE}"
  echo "REMOTE_STUB_IMAGE=${REMOTE_STUB_IMAGE}"
  echo "NEURON_HTTP_PORT=${NEURON_HTTP_PORT}"
  echo "REMOTE_STUB_HTTP_PORT=${REMOTE_STUB_HTTP_PORT}"
  echo "TZ=${TZ:-UTC}"
  echo "NEURON_LOG_LEVEL=${NEURON_LOG_LEVEL:-info}"
  echo "REMOTE_NEURON_TOKEN=${REMOTE_NEURON_TOKEN:-}"
  echo "REMOTE_TLS_INSECURE=${REMOTE_TLS_INSECURE:-0}"
} > "${ENV_TMP}"

REMOTE_TAR="/tmp/neuron-stack-deploy-${SAFE_TAG}.tar"
COMPOSE_TMP="/tmp/docker-compose.minipc.$$.yml"
NGINX_TMP="/tmp/nginx.minipc.$$.conf"
ENV_REMOTE="/tmp/minipc.env.$$"

echo ">> scp → ${MINIPC_SSH}"
scp -q "${STACK_TAR}" "${MINIPC_SSH}:${REMOTE_TAR}"
scp -q "${ROOT_DIR}/deploy/minipc/docker-compose.yml" "${MINIPC_SSH}:${COMPOSE_TMP}"
scp -q "${ROOT_DIR}/deploy/minipc/nginx.conf" "${MINIPC_SSH}:${NGINX_TMP}"
scp -q "${ENV_TMP}" "${MINIPC_SSH}:${ENV_REMOTE}"
rm -f "${ENV_TMP}"
[[ -n "${CLEANUP_LOCAL_TAR}" ]] && rm -f "${CLEANUP_LOCAL_TAR}"

echo ">> ssh: cài Docker (nếu cần), docker load, compose up"
ssh -tt "${MINIPC_SSH}" \
  INSTALL_DIR="${INSTALL_DIR}" \
  NEURON_IMAGE="${NEURON_IMAGE}" \
  REMOTE_TAR="${REMOTE_TAR}" \
  COMPOSE_TMP="${COMPOSE_TMP}" \
  NGINX_TMP="${NGINX_TMP}" \
  ENV_REMOTE="${ENV_REMOTE}" \
  SKIP_DOCKER_ON_REMOTE="${SKIP_DOCKER_ON_REMOTE}" \
  REMOVE_REMOTE_TAR_AFTER="${REMOVE_REMOTE_TAR_AFTER}" \
  bash -s <<'REMOTE'
set -euo pipefail
SUDO=""
if [[ "${EUID}" -ne 0 ]]; then
  SUDO="sudo"
fi

if command -v docker >/dev/null 2>&1; then
  echo ">> Docker đã có trên mini PC — không chạy get.docker.com."
else
  if [[ "${SKIP_DOCKER_ON_REMOTE}" == "1" ]]; then
    echo "ERROR: chưa có docker và SKIP_DOCKER_ON_REMOTE=1." >&2
    exit 1
  fi
  echo ">> Chưa có Docker — cài qua get.docker.com..."
  curl -fsSL https://get.docker.com | ${SUDO} sh
fi

if ! ${SUDO} docker compose version >/dev/null 2>&1; then
  echo "ERROR: cần Docker Compose v2 (plugin 'docker compose')." >&2
  exit 1
fi

echo ">> Thư mục ${INSTALL_DIR}"
${SUDO} mkdir -p "${INSTALL_DIR}/data/config" "${INSTALL_DIR}/data/logs" "${INSTALL_DIR}/data/persistence"
${SUDO} docker load -i "${REMOTE_TAR}"
NEURON_IMAGE="${NEURON_IMAGE:-}"
if [[ -n "${NEURON_IMAGE}" ]]; then
  CFG="${INSTALL_DIR}/data/config/default_plugins.json"
  if [[ ! -f "${CFG}" ]] || ! grep -q 'libplugin-s7comm\.so' "${CFG}" 2>/dev/null; then
    echo ">> Đồng bộ default_plugins.json từ image (S7 / plugin mới)"
    ${SUDO} docker run --rm "${NEURON_IMAGE}" cat /opt/neuron/config/default_plugins.json > /tmp/default_plugins.json
    ${SUDO} install -m 0644 /tmp/default_plugins.json "${CFG}"
    rm -f /tmp/default_plugins.json
  fi
fi
${SUDO} install -m 0644 "${COMPOSE_TMP}" "${INSTALL_DIR}/docker-compose.yml"
${SUDO} install -m 0644 "${NGINX_TMP}" "${INSTALL_DIR}/nginx.conf"
${SUDO} install -m 0600 "${ENV_REMOTE}" "${INSTALL_DIR}/.env"
rm -f "${COMPOSE_TMP}" "${NGINX_TMP}" "${ENV_REMOTE}"

if command -v systemctl >/dev/null 2>&1; then
  _frag="$(${SUDO} systemctl show -p FragmentPath --value neuron.service 2>/dev/null || true)"
  if [[ -n "${_frag}" ]]; then
    echo ">> Phát hiện neuron.service (Neuron native) — stop, disable, mask (chỉ chạy Neuron trong Docker)."
    ${SUDO} systemctl stop neuron.service 2>/dev/null || true
    ${SUDO} systemctl disable neuron.service 2>/dev/null || true
    ${SUDO} systemctl mask neuron.service 2>/dev/null || true
  fi
fi
unset _frag

echo ">> docker compose up -d"
( cd "${INSTALL_DIR}" && ${SUDO} docker compose up -d )
if grep -q 'libplugin-s7comm\.so' "${INSTALL_DIR}/data/config/default_plugins.json" 2>/dev/null; then
  ( cd "${INSTALL_DIR}" && ${SUDO} docker compose restart neuron ) || true
fi

if [[ "${REMOVE_REMOTE_TAR_AFTER}" == "1" ]]; then
  rm -f "${REMOTE_TAR}"
fi

echo ">> Xong trên mini PC."
REMOTE

if [[ "${NEURON_HTTP_PORT}" == "80" ]]; then
  echo ">> Hoàn tất. UI: http://<ip-mini-pc>/"
else
  echo ">> Hoàn tất. UI: http://<ip-mini-pc>:${NEURON_HTTP_PORT}/"
fi
