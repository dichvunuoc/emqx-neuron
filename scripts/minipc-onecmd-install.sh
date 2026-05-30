#!/usr/bin/env bash
# One-command deploy for Raspberry Pi mini PC.
# - Prompts SSH host/user when not provided.
# - Reuses existing stack tar if present; builds only when needed.
# - Falls back to interactive password prompt from ssh/scp when key is unavailable.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEPLOY_SCRIPT="${ROOT_DIR}/scripts/minipc-mac-ssh-deploy.sh"

DEFAULT_STACK_REGISTRY="${STACK_REGISTRY:-local/neuron}"
DEFAULT_STACK_TAG="${STACK_TAG:-cm4}"
DEFAULT_TAR="${ROOT_DIR}/neuron-stack-${DEFAULT_STACK_TAG//\//-}.tar"

SSH_TARGET="${MINIPC_SSH:-}"
HOST="${MINIPC_HOST:-}"
SSH_USER="${MINIPC_USER:-}"
INSTALL_DIR="${INSTALL_DIR:-/opt/neuron-minipc}"
STACK_TAR="${STACK_TAR_LOCAL:-}"
FORCE_BUILD="${FORCE_BUILD:-0}"

usage() {
  cat <<'HELP'
minipc-onecmd-install.sh — 1 command deploy Neuron full stack to Raspberry Pi

Usage:
  ./scripts/minipc-onecmd-install.sh [options]

Options:
  --ssh user@host        Full SSH target (highest priority)
  --host HOST            Hostname/IP (e.g. 10.8.0.14)
  --user USER            SSH username (e.g. pi, minipc)
  --install-dir PATH     Remote install dir (default: /opt/neuron-minipc)
  --tar PATH             Use existing stack tar (skip build)
  --force-build          Build/export tar even if a local tar exists
  -h, --help             Show help

Env defaults:
  STACK_REGISTRY=local/neuron
  STACK_TAG=cm4
  PLATFORM=linux/arm64
  NEURON_DOCKERFILE=Dockerfile.cm4

Examples:
  ./scripts/minipc-onecmd-install.sh
  ./scripts/minipc-onecmd-install.sh --host 10.8.0.14 --user pi
  STACK_TAG=cm4 ./scripts/minipc-onecmd-install.sh --ssh minipc-tamduong
HELP
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ssh)
      SSH_TARGET="${2:-}"
      shift 2
      ;;
    --host)
      HOST="${2:-}"
      shift 2
      ;;
    --user)
      SSH_USER="${2:-}"
      shift 2
      ;;
    --install-dir)
      INSTALL_DIR="${2:-}"
      shift 2
      ;;
    --tar)
      STACK_TAR="${2:-}"
      shift 2
      ;;
    --force-build)
      FORCE_BUILD=1
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

if [[ ! -x "${DEPLOY_SCRIPT}" ]]; then
  echo "ERROR: missing executable ${DEPLOY_SCRIPT}" >&2
  exit 1
fi

if [[ -z "${SSH_TARGET}" ]]; then
  if [[ -z "${HOST}" ]]; then
    read -r -p "MiniPC host/IP (e.g. 10.8.0.14 or minipc-tamduong): " HOST
  fi
  if [[ -z "${SSH_USER}" ]]; then
    read -r -p "SSH username [minipc]: " SSH_USER
    SSH_USER="${SSH_USER:-minipc}"
  fi
  SSH_TARGET="${SSH_USER}@${HOST}"
fi

if [[ -z "${STACK_TAR}" ]]; then
  STACK_TAR="${DEFAULT_TAR}"
fi

echo "== MiniPC one-command deploy =="
echo "Target            : ${SSH_TARGET}"
echo "Install dir       : ${INSTALL_DIR}"
echo "STACK_REGISTRY    : ${DEFAULT_STACK_REGISTRY}"
echo "STACK_TAG         : ${DEFAULT_STACK_TAG}"

if [[ "${FORCE_BUILD}" == "1" ]]; then
  echo "Stack source      : force build/export"
  RUN_MODE="build"
elif [[ -f "${STACK_TAR}" ]]; then
  echo "Stack source      : existing tar (${STACK_TAR})"
  RUN_MODE="tar"
else
  echo "Stack source      : tar missing, will build/export"
  RUN_MODE="build"
fi

echo "SSH note          : If key login is not set, scp/ssh will prompt password."

if ssh -o BatchMode=yes -o ConnectTimeout=5 "${SSH_TARGET}" "echo connected" >/dev/null 2>&1; then
  echo "SSH check         : key-based login available"
else
  echo "SSH check         : key login not ready (password prompt is expected)"
fi

if [[ "${RUN_MODE}" == "tar" ]]; then
  STACK_REGISTRY="${DEFAULT_STACK_REGISTRY}" \
  STACK_TAG="${DEFAULT_STACK_TAG}" \
  PLATFORM="${PLATFORM:-linux/arm64}" \
  NEURON_DOCKERFILE="${NEURON_DOCKERFILE:-Dockerfile.cm4}" \
  "${DEPLOY_SCRIPT}" --ssh "${SSH_TARGET}" --install-dir "${INSTALL_DIR}" --no-build --tar "${STACK_TAR}"
else
  STACK_REGISTRY="${DEFAULT_STACK_REGISTRY}" \
  STACK_TAG="${DEFAULT_STACK_TAG}" \
  PLATFORM="${PLATFORM:-linux/arm64}" \
  NEURON_DOCKERFILE="${NEURON_DOCKERFILE:-Dockerfile.cm4}" \
  "${DEPLOY_SCRIPT}" --ssh "${SSH_TARGET}" --install-dir "${INSTALL_DIR}"
fi

echo
echo "Deploy complete. Open: http://${HOST}/"
