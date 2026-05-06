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
#   IMAGE_TAR=/path/neuron.tar STUB_IMAGE_TAR=/path/stub.tar
#   SKIP_DOCKER_INSTALL=1
#
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/opt/neuron-minipc}"
SOURCE_BASE_URL="${SOURCE_BASE_URL:-}"
NEURON_IMAGE="${NEURON_IMAGE:-}"
REMOTE_STUB_IMAGE="${REMOTE_STUB_IMAGE:-}"
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

usage() {
  cat <<'HELP'
Usage:
  curl -fsSL <URL>/install-minipc-docker.sh | bash -s -- [options]

Options:
  --neuron-image TAG       Image for Neuron (required unless NEURON_IMAGE is set)
  --stub-image TAG         Image for remote backend stub (required unless REMOTE_STUB_IMAGE is set)
  --install-dir PATH       Install directory (default: /opt/neuron-minipc)
  --source-base-url URL    Raw GitHub base for deploy/minipc files (default: auto from INSTALL_SCRIPT_REPO)
  --skip-docker-install    Do not run get.docker.com bootstrap

Env:
  INSTALL_SCRIPT_REPO   owner/repo for GitHub raw paths (default: emqx/neuron)
  INSTALL_SCRIPT_BRANCH branch name (default: main)
  IMAGE_TAR             docker load this tar for Neuron image (optional)
  STUB_IMAGE_TAR        docker load this tar for stub image (optional)
HELP
}

INSTALL_SCRIPT_REPO="${INSTALL_SCRIPT_REPO:-emqx/neuron}"
INSTALL_SCRIPT_BRANCH="${INSTALL_SCRIPT_BRANCH:-main}"

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

if [[ -z "${SOURCE_BASE_URL}" ]]; then
  SOURCE_BASE_URL="https://raw.githubusercontent.com/${INSTALL_SCRIPT_REPO}/${INSTALL_SCRIPT_BRANCH}/deploy/minipc"
fi

if [[ -z "${NEURON_IMAGE}" || -z "${REMOTE_STUB_IMAGE}" ]]; then
  echo "ERROR: set --neuron-image and --stub-image (or NEURON_IMAGE / REMOTE_STUB_IMAGE)." >&2
  usage
  exit 1
fi

if [[ "${SKIP_DOCKER_INSTALL}" != "1" ]]; then
  if ! command -v docker >/dev/null 2>&1; then
    echo ">> Installing Docker..."
    curl -fsSL https://get.docker.com | ${SUDO} sh
  fi
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker not found. Install Docker or re-run without SKIP_DOCKER_INSTALL=1." >&2
  exit 1
fi

if ! DC version >/dev/null 2>&1; then
  echo "ERROR: 'docker compose' plugin missing. Install Docker Engine with Compose v2." >&2
  exit 1
fi

echo ">> Preparing ${INSTALL_DIR}"
${SUDO} mkdir -p "${INSTALL_DIR}/data/config" "${INSTALL_DIR}/data/logs" "${INSTALL_DIR}/data/persistence"

TMP="$(mktemp)"
curl -fsSL "${SOURCE_BASE_URL}/docker-compose.yml" -o "${TMP}"
${SUDO} install -m 0644 "${TMP}" "${INSTALL_DIR}/docker-compose.yml"
rm -f "${TMP}"

if [[ -f "${INSTALL_DIR}/.env" ]]; then
  echo ">> Keeping existing ${INSTALL_DIR}/.env"
else
  curl -fsSL "${SOURCE_BASE_URL}/.env.example" -o "${TMP}"
  sed \
    -e "s|^NEURON_IMAGE=.*|NEURON_IMAGE=${NEURON_IMAGE}|" \
    -e "s|^REMOTE_STUB_IMAGE=.*|REMOTE_STUB_IMAGE=${REMOTE_STUB_IMAGE}|" \
    "${TMP}" | ${SUDO} tee "${INSTALL_DIR}/.env" >/dev/null
  rm -f "${TMP}"
  ${SUDO} chmod 0600 "${INSTALL_DIR}/.env"
fi

if [[ "${EUID}" -ne 0 ]] && [[ -n "${USER:-}" ]]; then
  ${SUDO} chown -R "${USER}:$(id -gn)" "${INSTALL_DIR}"
fi

if [[ -n "${IMAGE_TAR:-}" ]]; then
  echo ">> docker load Neuron image from ${IMAGE_TAR}"
  DKR load -i "${IMAGE_TAR}"
fi
if [[ -n "${STUB_IMAGE_TAR:-}" ]]; then
  echo ">> docker load stub image from ${STUB_IMAGE_TAR}"
  DKR load -i "${STUB_IMAGE_TAR}"
fi

echo ">> docker pull images"
DKR pull "${NEURON_IMAGE}"
DKR pull "${REMOTE_STUB_IMAGE}"

echo ">> docker compose up -d"
( cd "${INSTALL_DIR}" && DC up -d )

echo ">> Neuron UI: http://127.0.0.1:7000/ (change port in .env if NEURON_HTTP_PORT is set)"
echo ">> Remote stub: http://127.0.0.1:18080/docs (change REMOTE_STUB_HTTP_PORT in .env if needed)"
echo "Done."
