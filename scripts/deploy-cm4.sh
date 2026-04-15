#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEPLOY_DIR="${ROOT_DIR}/deploy/cm4"
ENV_FILE="${DEPLOY_DIR}/.env"
IMAGE_TAR="${IMAGE_TAR:-}"

cd "${DEPLOY_DIR}"

mkdir -p data/config data/logs data/persistence data/dist

if [[ ! -f "${ENV_FILE}" ]]; then
  cp .env.example .env
  echo ">> Created deploy/cm4/.env from template"
fi

if [[ -n "${IMAGE_TAR}" ]]; then
  echo ">> Loading image tar: ${IMAGE_TAR}"
  docker load -i "${IMAGE_TAR}"
fi

echo ">> Starting Neuron container"
docker compose --env-file .env up -d

echo ">> Current status"
docker compose --env-file .env ps
