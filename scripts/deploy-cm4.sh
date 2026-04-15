#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEPLOY_DIR="${ROOT_DIR}/deploy/cm4"
ENV_FILE="${DEPLOY_DIR}/.env"
IMAGE_TAR="${IMAGE_TAR:-}"

DOCKER_CLI=()
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

resolve_docker_cli

cd "${DEPLOY_DIR}"

mkdir -p data/config data/logs data/persistence data/dist

if [[ ! -f "${ENV_FILE}" ]]; then
  cp .env.example .env
  echo ">> Created deploy/cm4/.env from template"
fi

if [[ -n "${IMAGE_TAR}" ]]; then
  echo ">> Loading image tar: ${IMAGE_TAR}"
  "${DOCKER_CLI[@]}" load -i "${IMAGE_TAR}"
fi

echo ">> Starting Neuron container"
"${DOCKER_CLI[@]}" compose --env-file .env up -d

echo ">> Current status"
"${DOCKER_CLI[@]}" compose --env-file .env ps
