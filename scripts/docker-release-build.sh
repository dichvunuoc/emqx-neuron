#!/usr/bin/env bash
# Một lệnh build (và push) **cả hai** image Neuron + remote-stub, cùng phiên bản.
#
# Cùng registry + tag (khuyên dùng):
#   STACK_REGISTRY=registry.example.com/iot STACK_TAG=1.0 ./scripts/docker-release-build.sh
#   PUSH=1 STACK_REGISTRY=my/reg STACK_TAG=1.0 PLATFORM=linux/arm64 NEURON_DOCKERFILE=Dockerfile.cm4 ./scripts/docker-release-build.sh
#
# Ghi đè tên image (tuỳ chọn):
#   NEURON_IMAGE=a/n:v1 REMOTE_STUB_IMAGE=a/s:v1 ./scripts/docker-release-build.sh
#
# Xuất một file tar chứa cả hai image (offline):
#   EXPORT_STACK_TAR=1 STACK_REGISTRY=reg.io/iot STACK_TAG=1.0 ./scripts/docker-release-build.sh
#   → neuron-stack-1.0.tar trong thư mục gốc repo
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

# shellcheck source=scripts/minipc-resolve-stack-images.sh
source "${ROOT_DIR}/scripts/minipc-resolve-stack-images.sh"
minipc_resolve_stack_images

NEURON_DOCKERFILE="${NEURON_DOCKERFILE:-Dockerfile}"
STUB_DOCKERFILE="${STUB_DOCKERFILE:-scripts/neuron-remote-control/demo/Dockerfile.backend-stub}"
PLATFORM="${PLATFORM:-}"
PUSH="${PUSH:-0}"
EXPORT_STACK_TAR="${EXPORT_STACK_TAR:-0}"
OUTPUT_STACK_TAR="${OUTPUT_STACK_TAR:-${ROOT_DIR}/neuron-stack-${STACK_TAG:-local}.tar}"

if [[ "${PUSH}" == "1" ]]; then
  echo "NOTE: PUSH=1 — đăng nhập registry: docker login" >&2
fi

build_neuron() {
  if [[ -n "${PLATFORM}" ]]; then
    if ! docker buildx version >/dev/null 2>&1; then
      echo "ERROR: cần docker buildx khi đặt PLATFORM." >&2
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
    local args=(buildx build --platform "${PLATFORM}" --file "${STUB_DOCKERFILE}" --tag "${REMOTE_STUB_IMAGE}")
    if [[ "${PUSH}" == "1" ]]; then
      docker "${args[@]}" --push .
    else
      docker "${args[@]}" --load .
    fi
  else
    docker build --file "${STUB_DOCKERFILE}" --tag "${REMOTE_STUB_IMAGE}" .
  fi
}

echo ">> Stack: Neuron=${NEURON_IMAGE} + stub=${REMOTE_STUB_IMAGE}"
echo ">> Neuron Dockerfile: ${NEURON_DOCKERFILE}"
build_neuron

echo ">> Stub Dockerfile: ${STUB_DOCKERFILE}"
build_stub

if [[ "${EXPORT_STACK_TAR}" == "1" ]]; then
  echo ">> docker save → ${OUTPUT_STACK_TAR}"
  docker save -o "${OUTPUT_STACK_TAR}" "${NEURON_IMAGE}" "${REMOTE_STUB_IMAGE}"
fi

echo ">> Xong."
