#!/usr/bin/env bash
# Build (and optionally push) Neuron + remote-stub images from this repo.
#
# Examples:
#   NEURON_IMAGE=my/neuron-full:v1 STUB_IMAGE=my/neuron-remote-stub:v1 ./scripts/docker-release-build.sh
#   PUSH=1 NEURON_IMAGE=registry.io/a/n:v1 STUB_IMAGE=registry.io/a/s:v1 ./scripts/docker-release-build.sh
#
# ARM64 Neuron (buildx):
#   NEURON_DOCKERFILE=Dockerfile.cm4 PLATFORM=linux/arm64 PUSH=1 ... ./scripts/docker-release-build.sh
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

NEURON_IMAGE="${NEURON_IMAGE:-neuron-full:local}"
STUB_IMAGE="${STUB_IMAGE:-neuron-remote-stub:local}"
NEURON_DOCKERFILE="${NEURON_DOCKERFILE:-Dockerfile}"
STUB_DOCKERFILE="${STUB_DOCKERFILE:-scripts/neuron-remote-control/demo/Dockerfile.backend-stub}"
PLATFORM="${PLATFORM:-}"
PUSH="${PUSH:-0}"

if [[ "${PUSH}" == "1" ]]; then
  echo "NOTE: PUSH=1 — ensure registry auth: docker login" >&2
fi

build_neuron() {
  if [[ -n "${PLATFORM}" ]]; then
    if ! docker buildx version >/dev/null 2>&1; then
      echo "ERROR: docker buildx required when PLATFORM is set." >&2
      exit 1
    fi
    local args=(buildx build --platform "${PLATFORM}" --file "${NEURON_DOCKERFILE}" --tag "${NEURON_IMAGE}")
    if [[ "${PUSH}" == "1" ]]; then
      docker "${args[@]}" --push .
    else
      docker "${args[@]}" --load .
    fi
  else
    docker build --file "${NEURON_DOCKERFILE}" --tag "${NEURON_IMAGE}" .
  fi
}

build_stub() {
  if [[ -n "${PLATFORM}" ]]; then
    local args=(buildx build --platform "${PLATFORM}" --file "${STUB_DOCKERFILE}" --tag "${STUB_IMAGE}")
    if [[ "${PUSH}" == "1" ]]; then
      docker "${args[@]}" --push .
    else
      docker "${args[@]}" --load .
    fi
  else
    docker build --file "${STUB_DOCKERFILE}" --tag "${STUB_IMAGE}" .
  fi
}

echo ">> Neuron image: ${NEURON_IMAGE} (${NEURON_DOCKERFILE})"
build_neuron

echo ">> Remote stub image: ${STUB_IMAGE} (${STUB_DOCKERFILE})"
build_stub

echo ">> Done."
