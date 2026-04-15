#!/usr/bin/env bash
# Neuron CM4 native installer (no Docker) — works with: curl -fsSL <URL> | bash
#
# Goal:
# - Fresh Raspberry Pi setup from zero.
# - Clone your published repo/branch.
# - Build Neuron from current source (includes your custom patches).
# - Optionally register systemd service for auto-start.
#
# Quick examples:
#   curl -fsSL https://raw.githubusercontent.com/<owner>/<repo>/<branch>/scripts/install-cm4-native-remote.sh | \
#     bash -s -- --repo https://github.com/<owner>/<repo>.git --branch main
#
#   curl -fsSL https://raw.githubusercontent.com/<owner>/<repo>/<branch>/scripts/install-cm4-native-remote.sh | \
#     bash -s -- --repo https://github.com/<owner>/<repo>.git --branch main --enable-service
#
# Optional env:
#   INSTALL_ROOT=/opt/neuron
#   SRC_DIR_NAME=emqx-neuron
#   BUILD_DIR=build-native-cm4
#   BUILD_TYPE=Release
#   BUILD_JOBS=2
#   DISABLE_DATALAYERS=1
#   SKIP_DASHBOARD=0
#
set -euo pipefail

INSTALL_ROOT="${INSTALL_ROOT:-/opt/neuron}"
SRC_DIR_NAME="${SRC_DIR_NAME:-emqx-neuron}"
BUILD_DIR="${BUILD_DIR:-build-native-cm4}"
BUILD_TYPE="${BUILD_TYPE:-Release}"
BUILD_JOBS="${BUILD_JOBS:-2}"
DISABLE_DATALAYERS="${DISABLE_DATALAYERS:-1}"
SKIP_DASHBOARD="${SKIP_DASHBOARD:-0}"

REPO_URL="${REPO_URL:-}"
REPO_BRANCH="${REPO_BRANCH:-main}"
ENABLE_SERVICE=0
SERVICE_NAME="${SERVICE_NAME:-neuron}"

SUDO=""
if [[ "${EUID}" -ne 0 ]]; then
  SUDO="sudo"
fi

usage() {
  cat <<'HELP'
Neuron CM4 native installer (no Docker)

Usage:
  curl -fsSL <URL>/install-cm4-native-remote.sh | bash -s -- [options]

Options:
  --repo URL            Git repo URL to clone (required)
  --branch NAME         Git branch/tag to checkout (default: main)
  --install-root PATH   Install root (default: /opt/neuron)
  --src-dir-name NAME   Source dir under install root (default: emqx-neuron)
  --build-dir NAME      Build directory name (default: build-native-cm4)
  --build-type TYPE     CMake build type (default: Release)
  --build-jobs N        Parallel build jobs (default: 2)
  --disable-datalayers  0/1, pass to build script (default: 1)
  --skip-dashboard      0/1, pass to build script (default: 0)
  --enable-service      Enable systemd service after build
  --service-name NAME   systemd service name (default: neuron)
  -h, --help            Show this help
HELP
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo)
        REPO_URL="${2:-}"
        shift 2
        ;;
      --branch)
        REPO_BRANCH="${2:-}"
        shift 2
        ;;
      --install-root)
        INSTALL_ROOT="${2:-}"
        shift 2
        ;;
      --src-dir-name)
        SRC_DIR_NAME="${2:-}"
        shift 2
        ;;
      --build-dir)
        BUILD_DIR="${2:-}"
        shift 2
        ;;
      --build-type)
        BUILD_TYPE="${2:-}"
        shift 2
        ;;
      --build-jobs)
        BUILD_JOBS="${2:-}"
        shift 2
        ;;
      --disable-datalayers)
        DISABLE_DATALAYERS="${2:-}"
        shift 2
        ;;
      --skip-dashboard)
        SKIP_DASHBOARD="${2:-}"
        shift 2
        ;;
      --enable-service)
        ENABLE_SERVICE=1
        shift
        ;;
      --service-name)
        SERVICE_NAME="${2:-}"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "Unknown option: $1" >&2
        usage
        exit 1
        ;;
    esac
  done
}

ensure_prereqs() {
  echo "==> Checking base prerequisites"

  if ! command -v apt-get >/dev/null 2>&1; then
    echo "ERROR: apt-get not found. This installer currently supports Debian/Ubuntu only." >&2
    exit 1
  fi

  local -a missing_pkgs=()

  command -v git >/dev/null 2>&1 || missing_pkgs+=("git")
  command -v curl >/dev/null 2>&1 || missing_pkgs+=("curl")
  command -v rg >/dev/null 2>&1 || missing_pkgs+=("ripgrep")

  # Keep TLS CA bundle present for HTTPS git/curl operations.
  if [[ ! -f /etc/ssl/certs/ca-certificates.crt ]]; then
    missing_pkgs+=("ca-certificates")
  fi

  if [[ ${#missing_pkgs[@]} -eq 0 ]]; then
    echo "==> All base prerequisites already installed"
    return
  fi

  echo "==> Missing packages: ${missing_pkgs[*]}"
  ${SUDO} apt-get update -qq
  ${SUDO} apt-get install -y -qq "${missing_pkgs[@]}"
}

prepare_workspace() {
  echo "==> Preparing workspace at ${INSTALL_ROOT}"
  ${SUDO} mkdir -p "${INSTALL_ROOT}"
  ${SUDO} chown -R "${USER}:$(id -gn "${USER}")" "${INSTALL_ROOT}"
}

sync_source() {
  local src_path="${INSTALL_ROOT}/${SRC_DIR_NAME}"
  if [[ -z "${REPO_URL}" ]]; then
    echo "ERROR: --repo is required" >&2
    exit 1
  fi

  if [[ -d "${src_path}/.git" ]]; then
    echo "==> Source exists, updating ${src_path}"
    git -C "${src_path}" fetch --all --tags
    git -C "${src_path}" checkout "${REPO_BRANCH}"
    git -C "${src_path}" pull --ff-only origin "${REPO_BRANCH}"
  else
    echo "==> Cloning ${REPO_URL} (${REPO_BRANCH})"
    git clone --depth 1 --branch "${REPO_BRANCH}" "${REPO_URL}" "${src_path}"
  fi
}

run_native_build() {
  local src_path="${INSTALL_ROOT}/${SRC_DIR_NAME}"
  local builder="${src_path}/scripts/build-native-cm4.sh"

  if [[ ! -f "${builder}" ]]; then
    echo "ERROR: Missing ${builder}" >&2
    echo "Please push scripts/build-native-cm4.sh to your repo first." >&2
    exit 1
  fi

  chmod +x "${builder}"
  echo "==> Building native Neuron from current source"
  (
    cd "${src_path}"
    BUILD_DIR="${BUILD_DIR}" \
    BUILD_TYPE="${BUILD_TYPE}" \
    BUILD_JOBS="${BUILD_JOBS}" \
    DISABLE_DATALAYERS="${DISABLE_DATALAYERS}" \
    SKIP_DASHBOARD="${SKIP_DASHBOARD}" \
    INSTALL_DEPS=1 \
    "${builder}"
  )
}

write_systemd_service() {
  local src_path="${INSTALL_ROOT}/${SRC_DIR_NAME}"
  local work_dir="${src_path}/${BUILD_DIR}"
  local service_file="/etc/systemd/system/${SERVICE_NAME}.service"

  echo "==> Writing systemd unit ${SERVICE_NAME}.service"
  ${SUDO} tee "${service_file}" >/dev/null <<EOF
[Unit]
Description=Neuron Native Service
After=network.target

[Service]
Type=simple
WorkingDirectory=${work_dir}
Environment=LD_LIBRARY_PATH=/usr/local/lib
ExecStart=${work_dir}/neuron --log
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

  ${SUDO} systemctl daemon-reload
  ${SUDO} systemctl enable --now "${SERVICE_NAME}"
}

post_summary() {
  local src_path="${INSTALL_ROOT}/${SRC_DIR_NAME}"
  local bin_path="${src_path}/${BUILD_DIR}/neuron"
  echo
  echo "==> Done"
  echo "Source: ${src_path}"
  echo "Binary: ${bin_path}"
  echo
  echo "Manual run:"
  echo "  cd ${src_path}/${BUILD_DIR}"
  echo "  LD_LIBRARY_PATH=/usr/local/lib:\$LD_LIBRARY_PATH ./neuron --log"
  if [[ "${ENABLE_SERVICE}" -eq 1 ]]; then
    echo
    echo "Service:"
    echo "  sudo systemctl status ${SERVICE_NAME}"
    echo "  journalctl -u ${SERVICE_NAME} -f"
  fi
}

main() {
  parse_args "$@"
  ensure_prereqs
  prepare_workspace
  sync_source
  run_native_build
  if [[ "${ENABLE_SERVICE}" -eq 1 ]]; then
    write_systemd_service
  fi
  post_summary
}

main "$@"
