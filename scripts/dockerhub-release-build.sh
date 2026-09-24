#!/usr/bin/env bash
# Build or publish the public all-in-one Neuron Remote image.
#
# Local smoke image (one platform, loaded into Docker):
#   PLATFORM=linux/arm64 ./scripts/dockerhub-release-build.sh
#
# Public multi-platform release:
#   PUSH=1 ./scripts/dockerhub-release-build.sh
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

IMAGE_REPO="${IMAGE_REPO:-dannvhy/neuron-remote}"
VERSION_TAG="${VERSION_TAG:-2.14.0-alpha-remote.1}"
PLATFORM="${PLATFORM:-linux/amd64,linux/arm64}"
PUSH="${PUSH:-0}"
TAG_LATEST="${TAG_LATEST:-1}"
RELEASE_VERSION="${RELEASE_VERSION:-${VERSION_TAG}}"
FULL_VCS_REF="${FULL_VCS_REF:-$(git rev-parse HEAD 2>/dev/null || echo unknown)}"
VCS_REF="${VCS_REF:-${FULL_VCS_REF}}"
BUILD_DATE="${BUILD_DATE:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
PUBLIC_SOURCE_REMOTE="${PUBLIC_SOURCE_REMOTE:-https://github.com/dichvunuoc/emqx-neuron.git}"
SOURCE_URL="${SOURCE_URL:-https://github.com/dichvunuoc/emqx-neuron/tree/${FULL_VCS_REF}}"

if [[ -n "$(git status --porcelain --untracked-files=normal 2>/dev/null || true)" && "${VCS_REF}" != *-dirty ]]; then
  VCS_REF="${VCS_REF}-dirty"
fi

if [[ "${PUSH}" != "0" && "${PUSH}" != "1" ]]; then
  echo "ERROR: PUSH phải là 0 hoặc 1." >&2
  exit 1
fi

if [[ "${TAG_LATEST}" != "0" && "${TAG_LATEST}" != "1" ]]; then
  echo "ERROR: TAG_LATEST phải là 0 hoặc 1." >&2
  exit 1
fi

if [[ "${PUSH}" == "1" && "${VCS_REF}" == *-dirty ]]; then
  echo "ERROR: từ chối push image build từ worktree chưa commit." >&2
  echo "Hãy commit và publish đúng source release trước khi phát hành image." >&2
  exit 1
fi

if [[ "${PUSH}" == "1" && ( "${FULL_VCS_REF}" == "unknown" || "${VCS_REF}" != "${FULL_VCS_REF}" ) ]]; then
  echo "ERROR: public release phải dùng đúng full Git commit SHA của HEAD." >&2
  exit 1
fi

if [[ "${PUSH}" == "1" ]]; then
  if [[ "${SOURCE_URL}" != *"${FULL_VCS_REF}"* ]]; then
    echo "ERROR: SOURCE_URL phải là URL bất biến có chứa full commit SHA ${FULL_VCS_REF}." >&2
    exit 1
  fi
  public_refs="$(git ls-remote "${PUBLIC_SOURCE_REMOTE}")"
  if ! grep -Eq "^${FULL_VCS_REF}[[:space:]]" <<<"${public_refs}"; then
    echo "ERROR: commit ${FULL_VCS_REF} chưa tồn tại trên public source remote." >&2
    echo "Hãy push branch/tag source trước khi phát hành image." >&2
    exit 1
  fi
fi

if [[ "${PUSH}" == "0" && "${PLATFORM}" == *,* ]]; then
  echo "ERROR: build local chỉ nhận một platform; đặt PLATFORM=linux/amd64 hoặc linux/arm64." >&2
  exit 1
fi

if [[ "${PUSH}" == "1" && \
      "${PLATFORM}" != "linux/amd64,linux/arm64" && \
      "${PLATFORM}" != "linux/arm64,linux/amd64" ]]; then
  echo "ERROR: PUSH=1 bắt buộc PLATFORM=linux/amd64,linux/arm64 để không ghi đè tag public bằng một kiến trúc." >&2
  exit 1
fi

case ",${PLATFORM}," in
  *,linux/amd64,*|*,linux/arm64,*) ;;
  *)
    echo "ERROR: PLATFORM phải chứa linux/amd64 hoặc linux/arm64." >&2
    exit 1
    ;;
esac

if [[ "${PLATFORM}" == *","* && "${PLATFORM}" != "linux/amd64,linux/arm64" && "${PLATFORM}" != "linux/arm64,linux/amd64" ]]; then
  echo "ERROR: release multi-arch chỉ hỗ trợ linux/amd64,linux/arm64." >&2
  exit 1
fi

if ! docker buildx version >/dev/null 2>&1; then
  echo "ERROR: cần Docker Buildx." >&2
  exit 1
fi

image_version="${IMAGE_REPO}:${VERSION_TAG}"
args=(
  buildx build
  --platform "${PLATFORM}"
  --file Dockerfile.remote
  --tag "${image_version}"
  --build-arg "RELEASE_VERSION=${RELEASE_VERSION}"
  --build-arg "VCS_REF=${VCS_REF}"
  --build-arg "BUILD_DATE=${BUILD_DATE}"
  --build-arg "SOURCE_URL=${SOURCE_URL}"
)

echo ">> Image: ${image_version}"
echo ">> Platform: ${PLATFORM}"
echo ">> Revision: ${VCS_REF}"

if [[ "${PUSH}" == "1" ]]; then
  if [[ "${TAG_LATEST}" == "1" ]]; then
    args+=(--tag "${IMAGE_REPO}:latest")
  fi
  args+=(--provenance=mode=max --sbom=true --push)
  docker "${args[@]}" .
  inspect_output="$(docker buildx imagetools inspect "${image_version}")"
  if ! grep -Fq 'linux/amd64' <<<"${inspect_output}" || \
     ! grep -Fq 'linux/arm64' <<<"${inspect_output}"; then
    echo "ERROR: manifest public thiếu linux/amd64 hoặc linux/arm64." >&2
    exit 1
  fi
  echo ">> Đã push và xác minh ${image_version} (linux/amd64 + linux/arm64)"
  if [[ "${TAG_LATEST}" == "1" ]]; then
    echo ">> Đã cập nhật ${IMAGE_REPO}:latest"
  fi
else
  args+=(--load)
  docker "${args[@]}" .
  actual_arch="$(docker image inspect --format '{{.Architecture}}' "${image_version}")"
  expected_arch="${PLATFORM#linux/}"
  if [[ "${actual_arch}" != "${expected_arch}" ]]; then
    echo "ERROR: image architecture=${actual_arch}, mong đợi ${expected_arch}." >&2
    exit 1
  fi
  echo ">> Đã load ${image_version} (${actual_arch})"
fi
