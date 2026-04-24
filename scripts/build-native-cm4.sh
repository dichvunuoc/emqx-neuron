#!/usr/bin/env bash
#
# Native build helper for Raspberry Pi CM4 / ARM64 (no Docker).
# Builds Neuron from the current source tree, including local modifications.
#
# Usage:
#   chmod +x scripts/build-native-cm4.sh
#   scripts/build-native-cm4.sh
#
# Optional env:
#   BUILD_DIR=build-native-cm4
#   BUILD_TYPE=Release
#   INSTALL_DEPS=1
#   BUILD_JOBS=$(nproc)
#   DISABLE_DATALAYERS=1
#   SKIP_DASHBOARD=0
#   DASHBOARD_MODE=auto   # auto|local|release|skip
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-build-native-cm4}"
BUILD_TYPE="${BUILD_TYPE:-Release}"
INSTALL_DEPS="${INSTALL_DEPS:-1}"
BUILD_JOBS="${BUILD_JOBS:-$(nproc)}"
DISABLE_DATALAYERS="${DISABLE_DATALAYERS:-1}"
SKIP_DASHBOARD="${SKIP_DASHBOARD:-0}"
DASHBOARD_MODE="${DASHBOARD_MODE:-auto}"

SUDO=""
if [[ "${EUID}" -ne 0 ]]; then
  SUDO="sudo"
fi

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

has_shared_lib() {
  local pattern="$1"
  local fallback_path="$2"

  if need_cmd ldconfig; then
    ldconfig -p | rg -q "${pattern}"
    return $?
  fi

  # Some minimal systems do not ship ldconfig in PATH.
  [[ -n "${fallback_path}" && -e "${fallback_path}" ]]
}

ensure_system_packages() {
  echo "==> Installing system packages"
  ${SUDO} apt-get update -qq
  ${SUDO} apt-get install -y -qq \
    build-essential cmake git pkg-config ca-certificates wget unzip curl python3 \
    libssl-dev libxml2-dev libmbedtls-dev libsqlite3-dev \
    libprotobuf-c-dev librdkafka-dev zlib1g-dev
}

ensure_dashboard_build_tools() {
  if ! need_cmd node; then
    echo "==> Installing Node.js + npm for dashboard build"
    ${SUDO} apt-get update -qq
    ${SUDO} apt-get install -y -qq nodejs npm
  fi

  if need_cmd yarn; then
    return
  fi

  if need_cmd corepack; then
    corepack enable >/dev/null 2>&1 || true
    corepack prepare yarn@stable --activate >/dev/null 2>&1 || true
  fi

  if ! need_cmd yarn; then
    echo "==> Installing yarn"
    ${SUDO} npm install -g yarn >/dev/null
  fi
}

build_zlog() {
  if has_shared_lib "libzlog\\.so" "/usr/local/lib/libzlog.so"; then
    echo "==> libzlog already available"
    return
  fi
  echo "==> Building zlog 1.2.15"
  rm -rf /tmp/zlog
  git clone --depth 1 --branch 1.2.15 https://github.com/HardySimpson/zlog.git /tmp/zlog
  make -C /tmp/zlog -j"${BUILD_JOBS}"
  ${SUDO} make -C /tmp/zlog install
}

build_jansson() {
  # Do not treat distro /lib/.../libjansson.so.4 as "ours"; libjwt needs CMake config from /usr/local.
  if [[ -f /usr/local/lib/libjansson.so ]] || [[ -f /usr/local/lib64/libjansson.so ]]; then
    echo "==> libjansson already available under /usr/local"
    return
  fi
  echo "==> Building neugates/jansson"
  rm -rf /tmp/jansson
  git clone --depth 1 https://github.com/neugates/jansson.git /tmp/jansson
  cmake -S /tmp/jansson -B /tmp/jansson/build \
    -DJANSSON_BUILD_DOCS=OFF \
    -DJANSSON_EXAMPLES=OFF
  cmake --build /tmp/jansson/build -j"${BUILD_JOBS}"
  ${SUDO} cmake --install /tmp/jansson/build
}

build_libjwt() {
  if has_shared_lib "libjwt\\.so" "/usr/local/lib/libjwt.so"; then
    echo "==> libjwt already available"
    return
  fi
  echo "==> Building libjwt v1.13.1"
  rm -rf /tmp/libjwt
  git clone --depth 1 --branch v1.13.1 https://github.com/benmcollins/libjwt.git /tmp/libjwt
  cmake -S /tmp/libjwt -B /tmp/libjwt/build \
    -DCMAKE_PREFIX_PATH=/usr/local \
    -DENABLE_PIC=ON \
    -DBUILD_SHARED_LIBS=ON
  cmake --build /tmp/libjwt/build -j"${BUILD_JOBS}"
  ${SUDO} cmake --install /tmp/libjwt/build
}

build_nanosdk() {
  if [[ -f /usr/local/include/nng/mqtt_client.h || -f /usr/include/nng/mqtt_client.h ]]; then
    echo "==> NanoSDK/nng mqtt headers already available"
    return
  fi
  echo "==> Building NanoSDK (nng + MQTT)"
  rm -rf /tmp/NanoSDK
  git clone --depth 1 https://github.com/neugates/NanoSDK.git /tmp/NanoSDK
  cmake -S /tmp/NanoSDK -B /tmp/NanoSDK/build \
    -DBUILD_SHARED_LIBS=ON \
    -DNNG_TESTS=OFF \
    -DNNG_ENABLE_MQTT=ON \
    -DNNG_ENABLE_SQLITE=ON \
    -DNNG_ENABLE_TLS=ON
  cmake --build /tmp/NanoSDK/build -j"${BUILD_JOBS}"
  ${SUDO} cmake --install /tmp/NanoSDK/build
}

build_open62541() {
  if has_shared_lib "libopen62541\\.so" "/usr/local/lib/libopen62541.so"; then
    echo "==> libopen62541 already available"
    return
  fi
  echo "==> Building open62541 v1.4.6 (for OPC UA plugin)"
  rm -rf /tmp/open62541
  git clone --depth 1 --branch v1.4.6 https://github.com/open62541/open62541.git /tmp/open62541
  cmake -S /tmp/open62541 -B /tmp/open62541/build \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=ON \
    -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=OFF
  cmake --build /tmp/open62541/build -j"${BUILD_JOBS}"
  ${SUDO} cmake --install /tmp/open62541/build
}

build_dashboard_local() {
  local dashboard_dir="${ROOT_DIR}/neuron-dashboard"
  local dist_dir="${ROOT_DIR}/${BUILD_DIR}/dist"

  if [[ ! -d "${dashboard_dir}" ]]; then
    return 1
  fi

  echo "==> Building dashboard from local source: ${dashboard_dir}"
  ensure_dashboard_build_tools
  (
    cd "${dashboard_dir}"
    yarn install --frozen-lockfile >/dev/null 2>&1 || yarn install
    yarn build
  )

  rm -rf "${dist_dir}"
  mkdir -p "${dist_dir}"

  if [[ -f "${dashboard_dir}/dist/index.html" ]]; then
    cp -a "${dashboard_dir}/dist/." "${dist_dir}/"
    return 0
  fi

  if [[ -f "${dashboard_dir}/dist/web/index.html" ]]; then
    cp -a "${dashboard_dir}/dist/web/." "${dist_dir}/"
    return
  fi

  echo "ERROR: Cannot find dashboard build output in ${dashboard_dir}/dist" >&2
  return 1
}

download_dashboard_release() {
  local dist_dir="${ROOT_DIR}/${BUILD_DIR}/dist"
  echo "==> Downloading dashboard release bundle"
  wget -q \
    https://github.com/emqx/neuron-dashboard/releases/download/2.6.3/neuron-dashboard.zip \
    -O /tmp/neuron-dashboard.zip
  unzip -q -o /tmp/neuron-dashboard.zip -d "${ROOT_DIR}/${BUILD_DIR}"
  rm -f /tmp/neuron-dashboard.zip

  if [[ ! -d "${dist_dir}" ]]; then
    echo "==> WARN: release bundle did not create ${dist_dir}"
  fi
}

prepare_dashboard() {
  local mode="${DASHBOARD_MODE}"
  if [[ "${SKIP_DASHBOARD}" == "1" ]]; then
    mode="skip"
  fi

  case "${mode}" in
    skip)
      echo "==> Skipping dashboard bundle"
      ;;
    local)
      if ! build_dashboard_local; then
        echo "ERROR: DASHBOARD_MODE=local but local dashboard build failed" >&2
        exit 1
      fi
      ;;
    release)
      download_dashboard_release
      ;;
    auto)
      if ! build_dashboard_local; then
        echo "==> Local dashboard not available, falling back to release bundle"
        download_dashboard_release
      fi
      ;;
    *)
      echo "ERROR: invalid DASHBOARD_MODE=${mode} (use auto|local|release|skip)" >&2
      exit 1
      ;;
  esac
}

build_neuron() {
  echo "==> Configuring CMake (${BUILD_TYPE})"
  cmake -S "${ROOT_DIR}" -B "${ROOT_DIR}/${BUILD_DIR}" \
    -DCMAKE_BUILD_TYPE="${BUILD_TYPE}" \
    -DDISABLE_UT=ON \
    -DDISABLE_ASAN=ON \
    -DDISABLE_WERROR=ON \
    -DDISABLE_DATALAYERS="${DISABLE_DATALAYERS}" \
    -DCMAKE_PREFIX_PATH=/usr/local \
    -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=OFF

  echo "==> Building neuron"
  cmake --build "${ROOT_DIR}/${BUILD_DIR}" -j"${BUILD_JOBS}"
}

post_check() {
  echo "==> Build output"
  ls -lh "${ROOT_DIR}/${BUILD_DIR}/neuron" "${ROOT_DIR}/${BUILD_DIR}/libneuron-base.so"

  echo "==> OPC UA plugin check"
  ls -lh "${ROOT_DIR}/${BUILD_DIR}/plugins/libplugin-opcua.so"

  echo
  echo "Build finished."
  echo "Run:"
  echo "  cd ${ROOT_DIR}/${BUILD_DIR}"
  echo "  LD_LIBRARY_PATH=/usr/local/lib:\$LD_LIBRARY_PATH ./neuron --log"
}

main() {
  if ! need_cmd rg; then
    echo "ERROR: ripgrep (rg) is required."
    exit 1
  fi

  if [[ "${INSTALL_DEPS}" == "1" ]]; then
    ensure_system_packages
    build_zlog
    build_jansson
    build_libjwt
    build_nanosdk
    build_open62541
    if need_cmd ldconfig; then
      ${SUDO} ldconfig
    else
      echo "==> WARN: ldconfig not found, skipping cache refresh"
    fi
  else
    echo "==> INSTALL_DEPS=0, skipping dependency installation"
  fi

  build_neuron
  prepare_dashboard
  post_check
}

main "$@"
