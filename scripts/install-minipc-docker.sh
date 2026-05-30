#!/usr/bin/env bash
# One-shot mini PC install: Docker (if needed) + pull/load images + compose up (Neuron + remote stub).
#
# Examples:
#   curl -fsSL https://raw.githubusercontent.com/<owner>/<repo>/main/scripts/install-minipc-docker.sh | \
#     bash -s -- --neuron-image registry.example.com/neuron-full:1.0 --stub-image registry.example.com/neuron-remote-stub:1.0
#
# Env (optional):
#   INSTALL_DIR=/opt/neuron-minipc
#   SOURCE_BASE_URL=https://raw.githubusercontent.com/<owner>/<repo>/main/deploy/minipc
#   STACK_REGISTRY=registry.example.com/iot  STACK_TAG=1.0   # cùng tag cho neuron-full + neuron-remote-stub
#   STACK_IMAGE_TAR=/path/neuron-stack-1.0.tar   # docker save cả hai (EXPORT_STACK_TAR=1 khi build)
#   IMAGE_TAR=/path/neuron.tar STUB_IMAGE_TAR=/path/stub.tar
#   SKIP_DOCKER_INSTALL=1
#   BUNDLE_DIR=/path/to/bundle  # thư mục chứa docker-compose.yml, nginx.conf, .env.example (offline/USB)
#
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/opt/neuron-minipc}"
SOURCE_BASE_URL="${SOURCE_BASE_URL:-}"
BUNDLE_DIR="${BUNDLE_DIR:-}"
NEURON_IMAGE="${NEURON_IMAGE:-}"
REMOTE_STUB_IMAGE="${REMOTE_STUB_IMAGE:-}"
STUB_IMAGE="${STUB_IMAGE:-}"
SKIP_DOCKER_INSTALL="${SKIP_DOCKER_INSTALL:-0}"
SKIP_DOCKER_PULL="${SKIP_DOCKER_PULL:-}"

SUDO=""
if [[ "${EUID}" -ne 0 ]]; then
  SUDO="sudo"
fi

DKR() {
  if [[ "${EUID}" -eq 0 ]] || groups | grep -q '\bdocker\b'; then
    docker "$@"
  else
    sudo docker "$@"
  fi
}

DC() {
  if [[ "${EUID}" -eq 0 ]] || groups | grep -q '\bdocker\b'; then
    docker compose "$@"
  else
    sudo docker compose "$@"
  fi
}

# Neuron cài qua .deb/apt thường có neuron.service — tắt để Docker không bị trùng cổng / hai bản chạy song song.
# Host mount ./data/config overrides image config. After upgrades, merge new default_plugins
# from the image so newly built drivers (e.g. S7) appear in the UI.
minipc_sync_default_plugins_from_image() {
  local cfg="${INSTALL_DIR}/data/config/default_plugins.json"
  local tmp
  tmp="$(mktemp)"
  if ! DKR run --rm "${NEURON_IMAGE}" cat /opt/neuron/config/default_plugins.json >"${tmp}" 2>/dev/null; then
    rm -f "${tmp}"
    return 0
  fi
  if [[ ! -f "${cfg}" ]]; then
    echo ">> Seed ${cfg} from image"
    ${SUDO} install -m 0644 "${tmp}" "${cfg}"
    rm -f "${tmp}"
    return 0
  fi
  if grep -q 'libplugin-s7comm\.so' "${cfg}" 2>/dev/null; then
    rm -f "${tmp}"
    return 0
  fi
  if grep -q 'libplugin-s7comm\.so' "${tmp}" 2>/dev/null; then
    echo ">> Cập nhật ${cfg} từ image (plugin mới, ví dụ S7)"
    ${SUDO} install -m 0644 "${tmp}" "${cfg}"
  fi
  rm -f "${tmp}"
}

minipc_disable_native_neuron() {
  if ! command -v systemctl >/dev/null 2>&1; then
    return 0
  fi
  local frag
  frag="$(${SUDO} systemctl show -p FragmentPath --value neuron.service 2>/dev/null || true)"
  if [[ -z "${frag}" ]]; then
    return 0
  fi
  echo ">> Phát hiện neuron.service (Neuron native) — stop, disable, mask (chỉ chạy Neuron trong Docker)."
  ${SUDO} systemctl stop neuron.service 2>/dev/null || true
  ${SUDO} systemctl disable neuron.service 2>/dev/null || true
  ${SUDO} systemctl mask neuron.service 2>/dev/null || true
}

usage() {
  cat <<'HELP'
Usage:
  curl -fsSL <URL>/install-minipc-docker.sh | bash -s -- [options]

Options:
  --neuron-image TAG       Image for Neuron (required unless NEURON_IMAGE is set)
  --stub-image TAG         Image for remote backend stub (required unless REMOTE_STUB_IMAGE is set)
  --install-dir PATH       Install directory (default: /opt/neuron-minipc)
  --source-base-url URL    Raw GitHub base for deploy/minipc files (default: auto from INSTALL_SCRIPT_REPO)
  --bundle-dir PATH        Dùng file local (docker-compose.yml, nginx.conf, .env.example) thay vì curl
  --skip-docker-install    Do not run get.docker.com bootstrap

Env:
  INSTALL_SCRIPT_REPO   owner/repo for GitHub raw paths (default: emqx/neuron)
  INSTALL_SCRIPT_BRANCH branch name (default: main)
  STACK_REGISTRY        + STACK_TAG → tự set NEURON_IMAGE / REMOTE_STUB_IMAGE (nếu chưa truyền --neuron-image)
  IMAGE_TAR             docker load this tar for Neuron image (optional)
  STUB_IMAGE_TAR        docker load this tar for stub image (optional)
  BUNDLE_DIR            giống --bundle-dir
  SKIP_DOCKER_PULL=1    Không chạy docker pull (offline). Mặc định: tự bật nếu có STACK_IMAGE_TAR.
HELP
}

INSTALL_SCRIPT_REPO="${INSTALL_SCRIPT_REPO:-emqx/neuron}"
INSTALL_SCRIPT_BRANCH="${INSTALL_SCRIPT_BRANCH:-main}"
STACK_REGISTRY="${STACK_REGISTRY:-}"
STACK_TAG="${STACK_TAG:-latest}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --neuron-image)
      NEURON_IMAGE="${2:-}"
      shift 2
      ;;
    --stub-image)
      REMOTE_STUB_IMAGE="${2:-}"
      shift 2
      ;;
    --install-dir)
      INSTALL_DIR="${2:-}"
      shift 2
      ;;
    --source-base-url)
      SOURCE_BASE_URL="${2:-}"
      shift 2
      ;;
    --bundle-dir)
      BUNDLE_DIR="${2:-}"
      shift 2
      ;;
    --skip-docker-install)
      SKIP_DOCKER_INSTALL=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -n "${BUNDLE_DIR}" ]]; then
  BUNDLE_DIR="$(cd "${BUNDLE_DIR}" && pwd)"
  for f in docker-compose.yml nginx.conf .env.example; do
    if [[ ! -f "${BUNDLE_DIR}/${f}" ]]; then
      echo "ERROR: --bundle-dir thiếu ${f} (${BUNDLE_DIR})" >&2
      exit 1
    fi
  done
elif [[ -z "${SOURCE_BASE_URL}" ]]; then
  SOURCE_BASE_URL="https://raw.githubusercontent.com/${INSTALL_SCRIPT_REPO}/${INSTALL_SCRIPT_BRANCH}/deploy/minipc"
fi

if [[ -n "${STACK_REGISTRY}" ]]; then
  NEURON_IMAGE="${NEURON_IMAGE:-${STACK_REGISTRY}/neuron-full:${STACK_TAG}}"
  REMOTE_STUB_IMAGE="${REMOTE_STUB_IMAGE:-${STUB_IMAGE:-${STACK_REGISTRY}/neuron-remote-stub:${STACK_TAG}}}"
fi

if [[ -z "${NEURON_IMAGE}" || -z "${REMOTE_STUB_IMAGE}" ]]; then
  echo "ERROR: set --neuron-image và --stub-image, hoặc STACK_REGISTRY (+ STACK_TAG), hoặc NEURON_IMAGE / REMOTE_STUB_IMAGE." >&2
  usage
  exit 1
fi

if [[ -z "${SKIP_DOCKER_PULL}" ]]; then
  if [[ -n "${STACK_IMAGE_TAR:-}" ]]; then
    SKIP_DOCKER_PULL=1
  else
    SKIP_DOCKER_PULL=0
  fi
fi

if command -v docker >/dev/null 2>&1; then
  echo ">> Docker already installed — skipping get.docker.com."
elif [[ "${SKIP_DOCKER_INSTALL}" == "1" ]]; then
  echo "ERROR: docker not found and SKIP_DOCKER_INSTALL=1." >&2
  exit 1
else
  echo ">> Installing Docker (get.docker.com)..."
  curl -fsSL https://get.docker.com | ${SUDO} sh
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker not found after install step." >&2
  exit 1
fi

if ! DC version >/dev/null 2>&1; then
  echo "ERROR: 'docker compose' plugin missing. Install Docker Engine with Compose v2." >&2
  exit 1
fi

echo ">> Preparing ${INSTALL_DIR}"
${SUDO} mkdir -p "${INSTALL_DIR}/data/config" "${INSTALL_DIR}/data/logs" "${INSTALL_DIR}/data/persistence"

ENV_EXAMPLE_SRC=""
if [[ -n "${BUNDLE_DIR}" ]]; then
  echo ">> Copy compose + nginx từ bundle ${BUNDLE_DIR}"
  ${SUDO} install -m 0644 "${BUNDLE_DIR}/docker-compose.yml" "${INSTALL_DIR}/docker-compose.yml"
  ${SUDO} install -m 0644 "${BUNDLE_DIR}/nginx.conf" "${INSTALL_DIR}/nginx.conf"
  ENV_EXAMPLE_SRC="${BUNDLE_DIR}/.env.example"
else
  local_tmp="$(mktemp)"
  curl -fsSL "${SOURCE_BASE_URL}/docker-compose.yml" -o "${local_tmp}"
  ${SUDO} install -m 0644 "${local_tmp}" "${INSTALL_DIR}/docker-compose.yml"
  rm -f "${local_tmp}"
  local_tmp="$(mktemp)"
  curl -fsSL "${SOURCE_BASE_URL}/nginx.conf" -o "${local_tmp}"
  ${SUDO} install -m 0644 "${local_tmp}" "${INSTALL_DIR}/nginx.conf"
  rm -f "${local_tmp}"
  ENV_EXAMPLE_SRC="$(mktemp)"
  curl -fsSL "${SOURCE_BASE_URL}/.env.example" -o "${ENV_EXAMPLE_SRC}"
fi

if [[ -f "${INSTALL_DIR}/.env" ]]; then
  echo ">> Keeping existing ${INSTALL_DIR}/.env"
else
  sed \
    -e "s|^NEURON_IMAGE=.*|NEURON_IMAGE=${NEURON_IMAGE}|" \
    -e "s|^REMOTE_STUB_IMAGE=.*|REMOTE_STUB_IMAGE=${REMOTE_STUB_IMAGE}|" \
    "${ENV_EXAMPLE_SRC}" | ${SUDO} tee "${INSTALL_DIR}/.env" >/dev/null
  ${SUDO} chmod 0600 "${INSTALL_DIR}/.env"
fi
if [[ -z "${BUNDLE_DIR}" && -n "${ENV_EXAMPLE_SRC}" ]]; then
  rm -f "${ENV_EXAMPLE_SRC}"
fi

if [[ "${EUID}" -ne 0 ]] && [[ -n "${USER:-}" ]]; then
  ${SUDO} chown -R "${USER}:$(id -gn)" "${INSTALL_DIR}"
fi

if [[ -n "${STACK_IMAGE_TAR:-}" ]]; then
  echo ">> docker load stack (2 images) from ${STACK_IMAGE_TAR}"
  DKR load -i "${STACK_IMAGE_TAR}"
fi
if [[ -n "${IMAGE_TAR:-}" ]]; then
  echo ">> docker load Neuron image from ${IMAGE_TAR}"
  DKR load -i "${IMAGE_TAR}"
fi
if [[ -n "${STUB_IMAGE_TAR:-}" ]]; then
  echo ">> docker load stub image from ${STUB_IMAGE_TAR}"
  DKR load -i "${STUB_IMAGE_TAR}"
fi

if [[ "${SKIP_DOCKER_PULL}" == "1" ]]; then
  echo ">> Bỏ qua docker pull (SKIP_DOCKER_PULL=1 hoặc đã dùng STACK_IMAGE_TAR)."
else
  echo ">> docker pull images"
  DKR pull "${NEURON_IMAGE}"
  DKR pull "${REMOTE_STUB_IMAGE}"
fi

minipc_disable_native_neuron

minipc_sync_default_plugins_from_image

echo ">> docker compose up -d"
( cd "${INSTALL_DIR}" && DC up -d )

if grep -q 'libplugin-s7comm\.so' "${INSTALL_DIR}/data/config/default_plugins.json" 2>/dev/null; then
  echo ">> Restart Neuron để nạp plugin mới từ default_plugins.json"
  ( cd "${INSTALL_DIR}" && DC restart neuron ) || true
fi

HTTP_PORT_LINE="$(grep -E '^NEURON_HTTP_PORT=' "${INSTALL_DIR}/.env" 2>/dev/null | tail -1 || true)"
HTTP_PORT="${NEURON_HTTP_PORT:-80}"
if [[ -n "${HTTP_PORT_LINE}" ]]; then
  HTTP_PORT="${HTTP_PORT_LINE#NEURON_HTTP_PORT=}"
fi
if [[ "${HTTP_PORT}" == "80" ]]; then
  echo ">> Neuron UI (qua proxy): http://127.0.0.1/"
else
  echo ">> Neuron UI (qua proxy): http://127.0.0.1:${HTTP_PORT}/"
fi
echo ">> Remote stub: http://127.0.0.1:${REMOTE_STUB_HTTP_PORT:-18080}/docs — chỉnh REMOTE_STUB_HTTP_PORT trong .env nếu cần"
echo "Done."
