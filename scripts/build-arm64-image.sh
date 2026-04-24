#!/usr/bin/env bash
set -euo pipefail

# Legacy script name kept for compatibility.
# Docker image build was removed; this script now produces a native tarball.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-build-native-cm4}"
OUTPUT_TAR="${OUTPUT_TAR:-neuron-native-arm64.tar.gz}"

if [[ ! -x "${ROOT_DIR}/scripts/build-native-cm4.sh" ]]; then
  chmod +x "${ROOT_DIR}/scripts/build-native-cm4.sh"
fi

"${ROOT_DIR}/scripts/build-native-cm4.sh"

if [[ ! -f "${ROOT_DIR}/${BUILD_DIR}/neuron" ]]; then
  echo "ERROR: native build output not found at ${ROOT_DIR}/${BUILD_DIR}/neuron" >&2
  exit 1
fi

echo "Creating native package ${OUTPUT_TAR}"
PACKAGE_ITEMS=(neuron)
[[ -d "${ROOT_DIR}/${BUILD_DIR}/plugins" ]] && PACKAGE_ITEMS+=(plugins)
[[ -d "${ROOT_DIR}/${BUILD_DIR}/config" ]] && PACKAGE_ITEMS+=(config)
tar -C "${ROOT_DIR}/${BUILD_DIR}" -czf "${ROOT_DIR}/${OUTPUT_TAR}" "${PACKAGE_ITEMS[@]}"
echo "Done: ${ROOT_DIR}/${OUTPUT_TAR}"
#!/usr/bin/env bash
set -euo pipefail

# Legacy script name kept for compatibility.
# Docker image build was removed; this script now produces a native tarball.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-build-native-cm4}"
OUTPUT_TAR="${OUTPUT_TAR:-neuron-native-arm64.tar.gz}"

if [[ ! -x "${ROOT_DIR}/scripts/build-native-cm4.sh" ]]; then
  chmod +x "${ROOT_DIR}/scripts/build-native-cm4.sh"
fi

"${ROOT_DIR}/scripts/build-native-cm4.sh"

if [[ ! -f "${ROOT_DIR}/${BUILD_DIR}/neuron" ]]; then
  echo "ERROR: native build output not found at ${ROOT_DIR}/${BUILD_DIR}/neuron" >&2
  exit 1
fi

echo "Creating native package ${OUTPUT_TAR}"
PACKAGE_ITEMS=(neuron)
[[ -d "${ROOT_DIR}/${BUILD_DIR}/plugins" ]] && PACKAGE_ITEMS+=(plugins)
[[ -d "${ROOT_DIR}/${BUILD_DIR}/config" ]] && PACKAGE_ITEMS+=(config)
tar -C "${ROOT_DIR}/${BUILD_DIR}" -czf "${ROOT_DIR}/${OUTPUT_TAR}" "${PACKAGE_ITEMS[@]}"
echo "Done: ${ROOT_DIR}/${OUTPUT_TAR}"
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_NAME="${IMAGE_NAME:-neuron:cm4}"
DOCKERFILE_PATH="${DOCKERFILE_PATH:-Dockerfile.cm4}"
PUSH_IMAGE="${PUSH_IMAGE:-0}"
EXPORT_TAR="${EXPORT_TAR:-0}"
OUTPUT_TAR="${OUTPUT_TAR:-neuron-cm4-image.tar}"
PLATFORM="${PLATFORM:-linux/arm64}"

cd "${ROOT_DIR}"

if ! docker buildx version >/dev/null 2>&1; then
  echo "docker buildx is required."
  exit 1
fi

echo ">> Building ${IMAGE_NAME} for ${PLATFORM} using ${DOCKERFILE_PATH}"

if [[ "${PUSH_IMAGE}" == "1" ]]; then
  docker buildx build \
    --platform "${PLATFORM}" \
    --file "${DOCKERFILE_PATH}" \
    --tag "${IMAGE_NAME}" \
    --push \
    .
elif [[ "${EXPORT_TAR}" == "1" ]]; then
  docker buildx build \
    --platform "${PLATFORM}" \
    --file "${DOCKERFILE_PATH}" \
    --tag "${IMAGE_NAME}" \
    --output "type=docker,dest=${OUTPUT_TAR}" \
    .
  echo ">> Image exported to ${ROOT_DIR}/${OUTPUT_TAR}"
else
  docker buildx build \
    --platform "${PLATFORM}" \
    --file "${DOCKERFILE_PATH}" \
    --tag "${IMAGE_NAME}" \
    --load \
    .
fi

echo ">> Build complete"
