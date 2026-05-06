#!/usr/bin/env bash
# Chạy trên CM4 / mini PC sau khi SSH (một file — có thể scp hoặc wget raw).
#
# Cài lần đầu (một registry + tag cho cả hai image):
#   export INSTALL_SCRIPT_REPO=dichvunuoc/emqx-neuron
#   export INSTALL_SCRIPT_BRANCH=main
#   export STACK_REGISTRY=your-registry/iot
#   export STACK_TAG=1.0-arm64
#   sudo bash minipc-cm4-edge.sh install
#
# Hoặc chỉ định từng image: NEURON_IMAGE=... REMOTE_STUB_IMAGE=...
#
# Cập nhật (kéo compose mới + image mới theo tag trong .env):
#   sudo bash minipc-cm4-edge.sh update
#
# Tuỳ chọn offline: STACK_IMAGE_TAR=neuron-stack.tar (một file từ EXPORT_STACK_TAR=1), hoặc IMAGE_TAR + STUB_IMAGE_TAR.
#
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/opt/neuron-minipc}"
META_FILE="${INSTALL_DIR}/.install-meta"
INSTALL_SCRIPT_REPO="${INSTALL_SCRIPT_REPO:-}"
INSTALL_SCRIPT_BRANCH="${INSTALL_SCRIPT_BRANCH:-main}"
SOURCE_BASE_URL="${SOURCE_BASE_URL:-}"
NEURON_IMAGE="${NEURON_IMAGE:-}"
REMOTE_STUB_IMAGE="${REMOTE_STUB_IMAGE:-}"
STUB_IMAGE="${STUB_IMAGE:-}"
STACK_REGISTRY="${STACK_REGISTRY:-}"
STACK_TAG="${STACK_TAG:-latest}"
SKIP_DOCKER_INSTALL="${SKIP_DOCKER_INSTALL:-0}"

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
minipc-cm4-edge.sh — cài / cập nhật Neuron + remote-stub (Docker) trên CM4

Cần set (lần install) hoặc đã có trong /opt/neuron-minipc/.env (lần update):

  INSTALL_SCRIPT_REPO    ví dụ: dichvunuoc/emqx-neuron
  INSTALL_SCRIPT_BRANCH   mặc định: main
  NEURON_IMAGE           tag image Neuron (nếu không dùng STACK_*)
  REMOTE_STUB_IMAGE      tag image stub
  STACK_REGISTRY         + STACK_TAG → .../neuron-full:TAG và .../neuron-remote-stub:TAG

Lệnh:
  install    Cài Docker (nếu thiếu), tải compose, tạo .env, pull/load, up -d
  update     Tải lại docker-compose.yml từ repo, docker compose pull, up -d

Tuỳ chọn:
  INSTALL_DIR              mặc định /opt/neuron-minipc
  SOURCE_BASE_URL          ghi đè URL raw deploy/minipc
  SKIP_DOCKER_INSTALL=1    không chạy get.docker.com
  STACK_IMAGE_TAR / IMAGE_TAR / STUB_IMAGE_TAR  docker load trước khi pull

Ví dụ update sau khi bạn đổi tag trong .env:
  sudo nano /opt/neuron-minipc/.env
  sudo bash minipc-cm4-edge.sh update
HELP
}

resolve_source_url() {
  if [[ -n "${SOURCE_BASE_URL}" ]]; then
    return
  fi
  if [[ -z "${INSTALL_SCRIPT_REPO}" ]]; then
    echo "ERROR: set INSTALL_SCRIPT_REPO (owner/repo) hoặc SOURCE_BASE_URL." >&2
    exit 1
  fi
  SOURCE_BASE_URL="https://raw.githubusercontent.com/${INSTALL_SCRIPT_REPO}/${INSTALL_SCRIPT_BRANCH}/deploy/minipc"
}

write_meta() {
  ${SUDO} mkdir -p "${INSTALL_DIR}"
  {
    echo "INSTALL_SCRIPT_REPO=${INSTALL_SCRIPT_REPO}"
    echo "INSTALL_SCRIPT_BRANCH=${INSTALL_SCRIPT_BRANCH}"
    echo "SOURCE_BASE_URL=${SOURCE_BASE_URL}"
  } | ${SUDO} tee "${META_FILE}" >/dev/null
  ${SUDO} chmod 0600 "${META_FILE}" 2>/dev/null || true
}

read_meta() {
  if [[ ! -f "${META_FILE}" ]]; then
    echo "ERROR: chưa cài đặt hoặc thiếu ${META_FILE}. Chạy: install" >&2
    exit 1
  fi
  set -a
  # shellcheck disable=SC1090
  source "${META_FILE}"
  set +a
  if [[ -z "${SOURCE_BASE_URL:-}" ]]; then
    if [[ -n "${INSTALL_SCRIPT_REPO:-}" ]]; then
      SOURCE_BASE_URL="https://raw.githubusercontent.com/${INSTALL_SCRIPT_REPO}/${INSTALL_SCRIPT_BRANCH}/deploy/minipc"
    else
      echo "ERROR: ${META_FILE} thiếu SOURCE_BASE_URL." >&2
      exit 1
    fi
  fi
}

ensure_docker() {
  if command -v docker >/dev/null 2>&1; then
    echo ">> Docker đã có — bỏ qua get.docker.com."
  elif [[ "${SKIP_DOCKER_INSTALL}" == "1" ]]; then
    echo "ERROR: chưa có docker và SKIP_DOCKER_INSTALL=1." >&2
    exit 1
  else
    echo ">> Chưa có Docker — cài qua get.docker.com..."
    curl -fsSL https://get.docker.com | ${SUDO} sh
  fi
  if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: không có docker." >&2
    exit 1
  fi
  if ! DC version >/dev/null 2>&1; then
    echo "ERROR: cần docker compose v2." >&2
    exit 1
  fi
}

cmd_install() {
  if [[ -n "${STACK_REGISTRY}" ]]; then
    NEURON_IMAGE="${NEURON_IMAGE:-${STACK_REGISTRY}/neuron-full:${STACK_TAG}}"
    REMOTE_STUB_IMAGE="${REMOTE_STUB_IMAGE:-${STUB_IMAGE:-${STACK_REGISTRY}/neuron-remote-stub:${STACK_TAG}}}"
  fi
  if [[ -z "${NEURON_IMAGE}" || -z "${REMOTE_STUB_IMAGE}" ]]; then
    echo "ERROR: export STACK_REGISTRY + STACK_TAG hoặc NEURON_IMAGE + REMOTE_STUB_IMAGE trước khi install." >&2
    usage
    exit 1
  fi
  resolve_source_url
  ensure_docker

  echo ">> Thư mục ${INSTALL_DIR}"
  ${SUDO} mkdir -p "${INSTALL_DIR}/data/config" "${INSTALL_DIR}/data/logs" "${INSTALL_DIR}/data/persistence"
  write_meta

  local tmp
  local tmp_nginx
  tmp="$(mktemp)"
  curl -fsSL "${SOURCE_BASE_URL}/docker-compose.yml" -o "${tmp}"
  ${SUDO} install -m 0644 "${tmp}" "${INSTALL_DIR}/docker-compose.yml"
  rm -f "${tmp}"
  tmp_nginx="$(mktemp)"
  curl -fsSL "${SOURCE_BASE_URL}/nginx.conf" -o "${tmp_nginx}"
  ${SUDO} install -m 0644 "${tmp_nginx}" "${INSTALL_DIR}/nginx.conf"
  rm -f "${tmp_nginx}"

  if [[ -f "${INSTALL_DIR}/.env" ]]; then
    echo ">> Giữ ${INSTALL_DIR}/.env (chỉnh tag rồi chạy update nếu đổi image)"
  else
    curl -fsSL "${SOURCE_BASE_URL}/.env.example" -o "${tmp}"
    sed \
      -e "s|^NEURON_IMAGE=.*|NEURON_IMAGE=${NEURON_IMAGE}|" \
      -e "s|^REMOTE_STUB_IMAGE=.*|REMOTE_STUB_IMAGE=${REMOTE_STUB_IMAGE}|" \
      "${tmp}" | ${SUDO} tee "${INSTALL_DIR}/.env" >/dev/null
    rm -f "${tmp}"
    ${SUDO} chmod 0600 "${INSTALL_DIR}/.env"
  fi

  if [[ "${EUID}" -ne 0 ]] && [[ -n "${USER:-}" ]]; then
    ${SUDO} chown -R "${USER}:$(id -gn)" "${INSTALL_DIR}"
  fi

  if [[ -n "${STACK_IMAGE_TAR:-}" ]]; then
    echo ">> docker load stack ${STACK_IMAGE_TAR}"
    DKR load -i "${STACK_IMAGE_TAR}"
  fi
  if [[ -n "${IMAGE_TAR:-}" ]]; then
    echo ">> docker load ${IMAGE_TAR}"
    DKR load -i "${IMAGE_TAR}"
  fi
  if [[ -n "${STUB_IMAGE_TAR:-}" ]]; then
    echo ">> docker load ${STUB_IMAGE_TAR}"
    DKR load -i "${STUB_IMAGE_TAR}"
  fi

  # shellcheck disable=SC1090
  set -a
  # shellcheck source=/dev/null
  source "${INSTALL_DIR}/.env"
  set +a

  echo ">> docker pull"
  DKR pull "${NEURON_IMAGE}"
  DKR pull "${REMOTE_STUB_IMAGE}"

  minipc_disable_native_neuron

  echo ">> docker compose up -d"
  ( cd "${INSTALL_DIR}" && DC up -d )

  echo ">> Xong. UI: http://$(hostname -I 2>/dev/null | awk '{print $1}' || echo 'IP-MINI-PC'):7000/"
  echo ">> Stub: port 18080 — xem .env (REMOTE_STUB_HTTP_PORT)."
}

cmd_update() {
  read_meta
  ensure_docker

  if [[ ! -f "${INSTALL_DIR}/.env" ]]; then
    echo "ERROR: thiếu ${INSTALL_DIR}/.env" >&2
    exit 1
  fi

  local tmp
  local tmp_nginx
  tmp="$(mktemp)"
  echo ">> Tải docker-compose.yml mới từ ${SOURCE_BASE_URL}"
  curl -fsSL "${SOURCE_BASE_URL}/docker-compose.yml" -o "${tmp}"
  ${SUDO} install -m 0644 "${tmp}" "${INSTALL_DIR}/docker-compose.yml"
  rm -f "${tmp}"
  echo ">> Tải nginx.conf mới từ ${SOURCE_BASE_URL}"
  tmp_nginx="$(mktemp)"
  curl -fsSL "${SOURCE_BASE_URL}/nginx.conf" -o "${tmp_nginx}"
  ${SUDO} install -m 0644 "${tmp_nginx}" "${INSTALL_DIR}/nginx.conf"
  rm -f "${tmp_nginx}"

  minipc_disable_native_neuron

  echo ">> docker compose pull && up -d"
  ( cd "${INSTALL_DIR}" && DC pull && DC up -d )

  echo ">> Cập nhật xong."
}

main() {
  local cmd="${1:-}"
  case "${cmd}" in
    install)
      cmd_install
      ;;
    update)
      cmd_update
      ;;
    -h|--help|help)
      usage
      exit 0
      ;;
    "")
      usage
      exit 0
      ;;
    *)
      echo "Unknown: ${cmd}" >&2
      usage
      exit 1
      ;;
  esac
}

main "$@"
