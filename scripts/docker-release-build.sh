#!/usr/bin/env bash
# Một lệnh build (và push) hai image ứng dụng Neuron + remote-stub, cùng phiên bản.
# Khi EXPORT_STACK_TAR=1, file offline chứa thêm image edge proxy Nginx.
#
# Cùng registry + tag (khuyên dùng):
#   STACK_REGISTRY=registry.example.com/iot STACK_TAG=1.0 ./scripts/docker-release-build.sh
#   PUSH=1 STACK_REGISTRY=my/reg STACK_TAG=1.0 PLATFORM=linux/arm64 NEURON_DOCKERFILE=Dockerfile.cm4 ./scripts/docker-release-build.sh
#
# Ghi đè tên image (tuỳ chọn):
#   NEURON_IMAGE=a/n:v1 REMOTE_STUB_IMAGE=a/s:v1 ./scripts/docker-release-build.sh
#
# Xuất một file tar chứa ba image (offline):
#   EXPORT_STACK_TAR=1 PLATFORM=linux/amd64 STACK_REGISTRY=reg.io/iot STACK_TAG=1.0 ./scripts/docker-release-build.sh
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
NGINX_IMAGE="${NGINX_IMAGE:-nginx:1.27-alpine}"
RELEASE_VERSION="${RELEASE_VERSION:-$(tr -d '[:space:]' < "${ROOT_DIR}/version")}"
VCS_REF="${VCS_REF:-$(git -C "${ROOT_DIR}" rev-parse --short=12 HEAD 2>/dev/null || echo unknown)}"
BUILD_DATE="${BUILD_DATE:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
SOURCE_URL="${SOURCE_URL:-https://github.com/dichvunuoc/emqx-neuron}"

if [[ -n "$(git -C "${ROOT_DIR}" status --porcelain --untracked-files=normal 2>/dev/null || true)" && "${VCS_REF}" != *-dirty ]]; then
  VCS_REF="${VCS_REF}-dirty"
fi

if [[ ( "${PUSH}" == "1" || "${EXPORT_STACK_TAR}" == "1" ) && -z "${PLATFORM}" ]]; then
  echo "ERROR: PUSH=1 và EXPORT_STACK_TAR=1 yêu cầu PLATFORM=linux/amd64 hoặc PLATFORM=linux/arm64." >&2
  exit 1
fi

if [[ -n "${PLATFORM}" && "${PLATFORM}" != "linux/amd64" && "${PLATFORM}" != "linux/arm64" ]]; then
  echo "ERROR: PLATFORM không được hỗ trợ: ${PLATFORM}. Chọn linux/amd64 hoặc linux/arm64." >&2
  exit 1
fi

if [[ "${NEURON_IMAGE}" == "${REMOTE_STUB_IMAGE}" || \
      "${NEURON_IMAGE}" == "${NGINX_IMAGE}" || \
      "${REMOTE_STUB_IMAGE}" == "${NGINX_IMAGE}" ]]; then
  echo "ERROR: NEURON_IMAGE, REMOTE_STUB_IMAGE và NGINX_IMAGE phải là ba tag khác nhau." >&2
  exit 1
fi

if [[ "${PUSH}" == "1" ]]; then
  echo "NOTE: PUSH=1 — đăng nhập registry: docker login" >&2
fi

if [[ "${PUSH}" == "1" && "${EXPORT_STACK_TAR}" == "1" ]]; then
  echo "ERROR: không hỗ trợ PUSH=1 cùng EXPORT_STACK_TAR=1 vì buildx --push không nạp image vào Docker local." >&2
  echo "Hãy chạy build/push và build/export thành hai lệnh riêng." >&2
  exit 1
fi

case "${PLATFORM}:${NEURON_DOCKERFILE}" in
  linux/arm64:Dockerfile)
    echo "ERROR: Dockerfile dùng toolchain x86_64; với PLATFORM=linux/arm64 hãy đặt NEURON_DOCKERFILE=Dockerfile.cm4." >&2
    exit 1
    ;;
  linux/amd64:Dockerfile.cm4)
    echo "ERROR: Dockerfile.cm4 dành cho ARM64; với PLATFORM=linux/amd64 hãy dùng NEURON_DOCKERFILE=Dockerfile." >&2
    exit 1
    ;;
esac

build_neuron() {
  if [[ -n "${PLATFORM}" ]]; then
    if ! docker buildx version >/dev/null 2>&1; then
      echo "ERROR: cần docker buildx khi đặt PLATFORM." >&2
      exit 1
    fi
    local args=(
      buildx build
      --platform "${PLATFORM}"
      --file "${NEURON_DOCKERFILE}"
      --tag "${NEURON_IMAGE}"
      --build-arg "RELEASE_VERSION=${RELEASE_VERSION}"
      --build-arg "VCS_REF=${VCS_REF}"
      --build-arg "BUILD_DATE=${BUILD_DATE}"
      --build-arg "SOURCE_URL=${SOURCE_URL}"
    )
    if [[ "${PUSH}" == "1" ]]; then
      docker "${args[@]}" --push .
    else
      docker "${args[@]}" --load .
    fi
  else
    docker build \
      --file "${NEURON_DOCKERFILE}" \
      --tag "${NEURON_IMAGE}" \
      --build-arg "RELEASE_VERSION=${RELEASE_VERSION}" \
      --build-arg "VCS_REF=${VCS_REF}" \
      --build-arg "BUILD_DATE=${BUILD_DATE}" \
      --build-arg "SOURCE_URL=${SOURCE_URL}" \
      .
  fi
}

build_stub() {
  if [[ -n "${PLATFORM}" ]]; then
    local args=(
      buildx build
      --platform "${PLATFORM}"
      --file "${STUB_DOCKERFILE}"
      --tag "${REMOTE_STUB_IMAGE}"
      --build-arg "RELEASE_VERSION=${RELEASE_VERSION}"
      --build-arg "VCS_REF=${VCS_REF}"
      --build-arg "BUILD_DATE=${BUILD_DATE}"
      --build-arg "SOURCE_URL=${SOURCE_URL}"
    )
    if [[ "${PUSH}" == "1" ]]; then
      docker "${args[@]}" --push .
    else
      docker "${args[@]}" --load .
    fi
  else
    docker build \
      --file "${STUB_DOCKERFILE}" \
      --tag "${REMOTE_STUB_IMAGE}" \
      --build-arg "RELEASE_VERSION=${RELEASE_VERSION}" \
      --build-arg "VCS_REF=${VCS_REF}" \
      --build-arg "BUILD_DATE=${BUILD_DATE}" \
      --build-arg "SOURCE_URL=${SOURCE_URL}" \
      .
  fi
}

verify_image_platform() {
  local image="$1"
  local expected_arch
  local actual_arch
  expected_arch="${PLATFORM#linux/}"
  expected_arch="${expected_arch%%/*}"
  actual_arch="$(docker image inspect --format '{{.Architecture}}' "${image}")"
  case "${expected_arch}" in aarch64) expected_arch=arm64 ;; x86_64) expected_arch=amd64 ;; esac
  case "${actual_arch}" in aarch64) actual_arch=arm64 ;; x86_64) actual_arch=amd64 ;; esac
  if [[ "${actual_arch}" != "${expected_arch}" ]]; then
    echo "ERROR: ${image} có architecture=${actual_arch}, mong đợi ${expected_arch}." >&2
    exit 1
  fi
}

echo ">> Stack: Neuron=${NEURON_IMAGE} + stub=${REMOTE_STUB_IMAGE}"
echo ">> Version=${RELEASE_VERSION} revision=${VCS_REF}"
echo ">> Neuron Dockerfile: ${NEURON_DOCKERFILE}"
build_neuron

echo ">> Stub Dockerfile: ${STUB_DOCKERFILE}"
build_stub

if [[ "${EXPORT_STACK_TAR}" == "1" ]]; then
  echo ">> Pull edge proxy ${NGINX_IMAGE}${PLATFORM:+ (${PLATFORM})}"
  if [[ -n "${PLATFORM}" ]]; then
    docker pull --platform "${PLATFORM}" "${NGINX_IMAGE}"
  else
    docker pull "${NGINX_IMAGE}"
  fi
  verify_image_platform "${NEURON_IMAGE}"
  verify_image_platform "${REMOTE_STUB_IMAGE}"
  verify_image_platform "${NGINX_IMAGE}"
  echo ">> docker save → ${OUTPUT_STACK_TAR}"
  docker save -o "${OUTPUT_STACK_TAR}" "${NEURON_IMAGE}" "${REMOTE_STUB_IMAGE}" "${NGINX_IMAGE}"
fi

echo ">> Xong."
