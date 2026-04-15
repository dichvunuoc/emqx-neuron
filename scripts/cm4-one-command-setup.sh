#!/usr/bin/env bash
set -euo pipefail

# One-command bootstrap for CM4:
# - install Docker (if missing)
# - prepare deploy files and data dirs
# - optionally load image from tar
# - start Neuron with docker compose

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEPLOY_DIR="${ROOT_DIR}/deploy/cm4"
ENV_FILE="${DEPLOY_DIR}/.env"
IMAGE_TAR="${IMAGE_TAR:-}"

SUDO=""
if [[ "${EUID}" -ne 0 ]]; then
  SUDO="sudo"
fi

DOCKER_CLI=()

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

resolve_docker_cli() {
  if [[ "${EUID}" -eq 0 ]]; then
    DOCKER_CLI=(docker)
    return
  fi
  if docker info >/dev/null 2>&1; then
    DOCKER_CLI=(docker)
    return
  fi
  if sudo docker info >/dev/null 2>&1; then
    DOCKER_CLI=(sudo docker)
    echo ">> Using sudo docker (re-login or newgrp docker to use docker without sudo)"
    return
  fi
  echo "ERROR: Cannot connect to Docker daemon." >&2
  exit 1
}

ensure_prereqs() {
  echo ">> Ensuring system prerequisites"
  ${SUDO} apt-get update -qq
  ${SUDO} apt-get install -y -qq ca-certificates curl gnupg lsb-release
}

ensure_docker() {
  if need_cmd docker; then
    echo ">> Docker already installed"
  else
    echo ">> Installing Docker (official script)"
    curl -fsSL https://get.docker.com | ${SUDO} sh
  fi

  ${SUDO} systemctl enable --now docker

  # Add current user to docker group for later sessions.
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
      echo ">> Added ${USER} to docker group (re-login needed to apply shell group)."
    fi
  fi
}

ensure_compose() {
  if "${DOCKER_CLI[@]}" compose version >/dev/null 2>&1; then
    echo ">> Docker Compose plugin available"
    return
  fi

  echo ">> Installing docker compose plugin"
  ${SUDO} apt-get install -y -qq docker-compose-plugin || true

  if ! "${DOCKER_CLI[@]}" compose version >/dev/null 2>&1; then
    echo "ERROR: docker compose plugin is unavailable. Install it and rerun."
    exit 1
  fi
}

prepare_runtime() {
  cd "${DEPLOY_DIR}"
  mkdir -p data/config data/logs data/persistence data/dist
  if [[ ! -f "${ENV_FILE}" ]]; then
    cp .env.example .env
    echo ">> Created deploy/cm4/.env from template"
  fi
}

load_or_pull_image() {
  cd "${DEPLOY_DIR}"
  if [[ -n "${IMAGE_TAR}" ]]; then
    echo ">> Loading image tar: ${IMAGE_TAR}"
    "${DOCKER_CLI[@]}" load -i "${IMAGE_TAR}"
    return
  fi

  # Pull image if NEURON_IMAGE is configured.
  if [[ -f .env ]]; then
    # shellcheck disable=SC1091
    source .env
    if [[ -n "${NEURON_IMAGE:-}" ]]; then
      echo ">> Pulling image: ${NEURON_IMAGE}"
      "${DOCKER_CLI[@]}" pull "${NEURON_IMAGE}" || true
    fi
  fi
}

deploy() {
  cd "${ROOT_DIR}"
  "${ROOT_DIR}/scripts/deploy-cm4.sh"
}

post_check() {
  cd "${DEPLOY_DIR}"
  echo ">> Smoke check"
  "${DOCKER_CLI[@]}" compose --env-file .env ps
  if curl -fsS "http://127.0.0.1:${NEURON_HTTP_PORT:-7000}" >/dev/null; then
    echo ">> UI/API reachable"
  else
    echo ">> UI/API not ready yet. Check: ${DOCKER_CLI[*]} compose --env-file .env logs --tail=200 neuron"
  fi
}

main() {
  echo "== Neuron CM4 one-command setup =="
  ensure_prereqs
  ensure_docker
  resolve_docker_cli
  ensure_compose
  prepare_runtime
  load_or_pull_image
  deploy
  post_check
  echo "== Done =="
}

main "$@"
