#!/usr/bin/env bash
# Neuron CM4 remote installer — works with: curl -fsSL <URL> | bash
# No git clone required. Downloads compose + env template, installs Docker, runs container.
#
# Examples (this fork hosts deploy/cm4 + this script):
#   curl -fsSL https://raw.githubusercontent.com/dichvunuoc/emqx-neuron/main/scripts/install-cm4-remote.sh | bash -s -- --image emqx/neuron:latest
#
#   NEURON_IMAGE=registry.example.com/neuron:cm4 \
#   curl -fsSL https://raw.githubusercontent.com/dichvunuoc/emqx-neuron/main/scripts/install-cm4-remote.sh | bash
#
# Env (optional):
#   INSTALL_DIR       default /opt/neuron-cm4
#   NEURON_IMAGE      Docker image (also use --image)
#   INSTALL_SCRIPT_REPO / INSTALL_SCRIPT_BRANCH — default dichvunuoc/emqx-neuron + main; used to build default SOURCE_BASE_URL
#   SOURCE_BASE_URL   override: base URL for docker-compose.yml and .env.example (trailing / optional)
#   IMAGE_TAR         if set, docker load from this path instead of docker pull
#   USE_PUBLIC_IMAGE  if 1 and NEURON_IMAGE unset, use emqx/neuron:latest in .env

set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/opt/neuron-cm4}"
INSTALL_SCRIPT_REPO="${INSTALL_SCRIPT_REPO:-dichvunuoc/emqx-neuron}"
INSTALL_SCRIPT_BRANCH="${INSTALL_SCRIPT_BRANCH:-main}"
SOURCE_BASE_URL="${SOURCE_BASE_URL:-https://raw.githubusercontent.com/${INSTALL_SCRIPT_REPO}/${INSTALL_SCRIPT_BRANCH}/deploy/cm4/}"
NEURON_IMAGE="${NEURON_IMAGE:-}"
IMAGE_TAR="${IMAGE_TAR:-}"
USE_PUBLIC_IMAGE="${USE_PUBLIC_IMAGE:-0}"

SUDO=""
if [[ "${EUID}" -ne 0 ]]; then
  SUDO="sudo"
fi

# Populated by resolve_docker_cli(): (docker) or (sudo docker)
DOCKER_CLI=()

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

# After usermod -aG docker, the current shell is still without the docker group until re-login.
# Use sudo docker for pull/compose in that case so the install finishes in one run.
resolve_docker_cli() {
  if [[ "${EUID}" -eq 0 ]]; then
    DOCKER_CLI=(docker)
    echo ">> Docker CLI: docker (root)"
    return
  fi
  if docker info >/dev/null 2>&1; then
    DOCKER_CLI=(docker)
    echo ">> Docker CLI: docker"
    return
  fi
  if sudo docker info >/dev/null 2>&1; then
    DOCKER_CLI=(sudo docker)
    echo ">> Docker CLI: sudo docker (session not in docker group yet — re-login or run: newgrp docker)"
    return
  fi
  echo "ERROR: Cannot connect to Docker daemon. Is docker.service running? Try: sudo systemctl status docker" >&2
  exit 1
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --image)
        NEURON_IMAGE="${2:-}"
        shift 2
        ;;
      --source-base)
        SOURCE_BASE_URL="${2:-}"
        shift 2
        ;;
      --install-dir)
        INSTALL_DIR="${2:-}"
        shift 2
        ;;
      --image-tar)
        IMAGE_TAR="${2:-}"
        shift 2
        ;;
      --public-image)
        USE_PUBLIC_IMAGE=1
        shift
        ;;
      -h|--help)
        cat <<'HELP'
Neuron CM4 remote install (no git clone).

Usage:
  curl -fsSL <URL>/install-cm4-remote.sh | bash -s -- [options]

Options:
  --image REF          Docker image to run (recommended: emqx/neuron:latest or your registry)
  --source-base URL    Where to fetch docker-compose.yml and .env.example (GitHub raw path)
  --install-dir PATH   Install root (default: /opt/neuron-cm4)
  --image-tar PATH     Load image from tar instead of docker pull
  --public-image       Set NEURON_IMAGE=emqx/neuron:latest in .env if not set

Environment:
  NEURON_IMAGE, SOURCE_BASE_URL, INSTALL_DIR, IMAGE_TAR, USE_PUBLIC_IMAGE=1
  INSTALL_SCRIPT_REPO, INSTALL_SCRIPT_BRANCH (defaults: dichvunuoc/emqx-neuron, main)
HELP
        exit 0
        ;;
      *)
        echo "Unknown option: $1 (use --help)" >&2
        exit 1
        ;;
    esac
  done
}

ensure_prereqs() {
  echo ">> Ensuring system prerequisites"
  ${SUDO} apt-get update -qq
  ${SUDO} apt-get install -y -qq ca-certificates curl
}

ensure_docker() {
  if need_cmd docker; then
    echo ">> Docker already installed"
  else
    echo ">> Installing Docker"
    curl -fsSL https://get.docker.com | ${SUDO} sh
  fi
  ${SUDO} systemctl enable --now docker

  if [[ -n "${SUDO}" ]]; then
    in_docker_group=0
    for grp in $(id -nG "${USER}"); do
      if [[ "${grp}" == "docker" ]]; then
        in_docker_group=1
        break
      fi
    done
    if [[ "${in_docker_group}" -eq 0 ]]; then
      ${SUDO} usermod -aG docker "${USER}" || true
      echo ">> Added ${USER} to docker group (log out and back in for group to apply)."
    fi
  fi
}

ensure_compose() {
  if "${DOCKER_CLI[@]}" compose version >/dev/null 2>&1; then
    return
  fi
  echo ">> Installing Docker Compose plugin"
  ${SUDO} apt-get install -y -qq docker-compose-plugin || true
  if ! "${DOCKER_CLI[@]}" compose version >/dev/null 2>&1; then
    echo "ERROR: docker compose plugin is required. Install docker-compose-plugin and retry." >&2
    exit 1
  fi
}

ensure_install_dir() {
  ${SUDO} mkdir -p "${INSTALL_DIR}"
  ${SUDO} chown -R "${USER}:$(id -gn "${USER}")" "${INSTALL_DIR}"
}

download_deploy_files() {
  local base="${SOURCE_BASE_URL}"
  [[ "${base}" == */ ]] || base="${base}/"
  echo ">> Downloading deploy files from ${base}"
  curl -fsSL "${base}docker-compose.yml" -o "${INSTALL_DIR}/docker-compose.yml"
  curl -fsSL "${base}.env.example" -o "${INSTALL_DIR}/.env.example"
}

set_env_kv() {
  local key="$1"
  local val="$2"
  local f="${INSTALL_DIR}/.env"
  if grep -q "^${key}=" "${f}" 2>/dev/null; then
    sed -i.bak "s|^${key}=.*|${key}=${val}|" "${f}" && rm -f "${f}.bak"
  else
    echo "${key}=${val}" >> "${f}"
  fi
}

prepare_env() {
  cd "${INSTALL_DIR}"
  mkdir -p data/config data/logs data/persistence data/dist
  local first=0
  if [[ ! -f .env ]]; then
    cp .env.example .env
    first=1
  fi

  if [[ "${USE_PUBLIC_IMAGE}" == "1" ]] && [[ -z "${NEURON_IMAGE}" ]]; then
    NEURON_IMAGE="emqx/neuron:latest"
  fi

  if [[ -n "${NEURON_IMAGE}" ]]; then
    # Escape sed special chars minimally: use | delimiter; avoid newlines in image ref
    set_env_kv "NEURON_IMAGE" "${NEURON_IMAGE}"
  fi

  # shellcheck disable=SC1091
  source .env

  if [[ "${first}" -eq 1 ]] && [[ -z "${NEURON_IMAGE:-}" ]]; then
    # .env from example may still say neuron:cm4 — warn if no custom image
    if grep -q '^NEURON_IMAGE=neuron:cm4' .env 2>/dev/null; then
      echo ">> Note: NEURON_IMAGE=neuron:cm4 expects a locally built tag. Run again with:" >&2
      echo "    curl ... | bash -s -- --image emqx/neuron:latest" >&2
      echo "    or: --image your.registry/neuron:cm4" >&2
    fi
  fi
}

load_or_pull_image() {
  cd "${INSTALL_DIR}"
  # shellcheck disable=SC1091
  source .env
  if [[ -n "${IMAGE_TAR}" ]]; then
    echo ">> Loading image from ${IMAGE_TAR}"
    "${DOCKER_CLI[@]}" load -i "${IMAGE_TAR}"
    return
  fi
  if [[ -n "${NEURON_IMAGE:-}" ]]; then
    echo ">> Pulling image: ${NEURON_IMAGE}"
    "${DOCKER_CLI[@]}" pull "${NEURON_IMAGE}"
  fi
}

deploy() {
  cd "${INSTALL_DIR}"
  echo ">> Starting Neuron"
  "${DOCKER_CLI[@]}" compose --env-file .env up -d
  "${DOCKER_CLI[@]}" compose --env-file .env ps
}

post_check() {
  cd "${INSTALL_DIR}"
  # shellcheck disable=SC1091
  source .env
  local port="${NEURON_HTTP_PORT:-7000}"
  echo ">> Smoke check http://127.0.0.1:${port}"
  if curl -fsS --connect-timeout 5 "http://127.0.0.1:${port}/" >/dev/null 2>&1; then
    echo ">> UI/API reachable"
  else
    echo ">> UI/API not ready yet. Try: cd ${INSTALL_DIR} && ${DOCKER_CLI[*]} compose --env-file .env logs --tail=200 neuron"
  fi
}

main() {
  echo "== Neuron CM4 remote install (no repo clone) =="
  echo ">> Install dir: ${INSTALL_DIR}"
  echo ">> Compose/env source: ${SOURCE_BASE_URL}"
  ensure_prereqs
  ensure_docker
  resolve_docker_cli
  ensure_compose
  ensure_install_dir
  download_deploy_files
  prepare_env
  load_or_pull_image
  deploy
  post_check
  echo "== Done. Data: ${INSTALL_DIR}/data =="
}

parse_args "$@"
main
