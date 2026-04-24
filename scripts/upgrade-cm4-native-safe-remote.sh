#!/usr/bin/env bash
# Safe one-command Neuron upgrade for miniPC/CM4:
# - Preserve existing Neuron runtime data/config.
# - Upgrade source + rebuild Neuron.
# - Restore runtime data/config.
# - Configure remote-control backend + UI proxy by default.

set -euo pipefail

INSTALL_ROOT="${INSTALL_ROOT:-/opt/neuron}"
SRC_DIR_NAME="${SRC_DIR_NAME:-emqx-neuron}"
BUILD_DIR="${BUILD_DIR:-build-native-cm4}"
SERVICE_NAME="${SERVICE_NAME:-neuron}"
REPO_URL="${REPO_URL:-}"
REPO_BRANCH="${REPO_BRANCH:-main}"
BUILD_TYPE="${BUILD_TYPE:-Release}"
BUILD_JOBS="${BUILD_JOBS:-2}"
DISABLE_DATALAYERS="${DISABLE_DATALAYERS:-1}"
SKIP_DASHBOARD="${SKIP_DASHBOARD:-0}"
DASHBOARD_MODE="${DASHBOARD_MODE:-auto}"
ENABLE_REMOTE_STUB="${ENABLE_REMOTE_STUB:-1}"
DIRTY_REPO_FALLBACK="${DIRTY_REPO_FALLBACK:-1}"
ENABLE_REMOTE_UI_PROXY="${ENABLE_REMOTE_UI_PROXY:-1}"
REMOTE_UI_PROXY_PORT="${REMOTE_UI_PROXY_PORT:-7002}"

REMOTE_STUB_SERVICE_NAME="${REMOTE_STUB_SERVICE_NAME:-neuron-remote-backend-stub}"
REMOTE_STUB_HOST="${REMOTE_STUB_HOST:-0.0.0.0}"
REMOTE_STUB_PORT="${REMOTE_STUB_PORT:-18080}"
REMOTE_STATE_DIR="${REMOTE_STATE_DIR:-/var/lib/neuron/remote-control}"
REMOTE_ENV_FILE="${REMOTE_ENV_FILE:-/etc/neuron/remote-control.env}"
REMOTE_VENV_DIR="${REMOTE_VENV_DIR:-/opt/neuron/venvs/remote-backend-stub}"
REMOTE_NEURON_BASE_URL="${REMOTE_NEURON_BASE_URL:-http://127.0.0.1:7000}"
REMOTE_NEURON_TOKEN="${REMOTE_NEURON_TOKEN:-}"
REMOTE_GATEWAY_ID="${REMOTE_GATEWAY_ID:-gw_default_001}"
REMOTE_CONTROL_SERVER_URL="${REMOTE_CONTROL_SERVER_URL:-wss://control.example.com/reverse-channel}"
REMOTE_AUTH_MODE="${REMOTE_AUTH_MODE:-mtls}"
REMOTE_HEARTBEAT_SEC="${REMOTE_HEARTBEAT_SEC:-20}"
REMOTE_RECONNECT_SEC="${REMOTE_RECONNECT_SEC:-3}"
REMOTE_DRYRUN_DEFAULT="${REMOTE_DRYRUN_DEFAULT:-true}"
REMOTE_HMAC_SECRET="${REMOTE_HMAC_SECRET:-}"

BACKUP_ROOT="${BACKUP_ROOT:-${INSTALL_ROOT}/backups}"
BACKUP_LABEL=""
BACKUP_PATH=""

SUDO=""
if [[ "${EUID}" -ne 0 ]]; then
  SUDO="sudo"
fi
HAS_SYSTEMCTL=0
if command -v systemctl >/dev/null 2>&1; then
  HAS_SYSTEMCTL=1
fi

usage() {
  cat <<'HELP'
Safe Neuron upgrade with runtime data preserved

Usage:
  scripts/upgrade-cm4-native-safe-remote.sh --repo <git-url> [options]

Required:
  --repo URL                         Git repo URL

Optional:
  --branch NAME                      Git branch/tag (default: main)
  --install-root PATH                Install root (default: /opt/neuron)
  --src-dir-name NAME                Source dir name (default: emqx-neuron)
  --build-dir NAME                   Build dir name (default: build-native-cm4)
  --service-name NAME                Neuron service name (default: neuron)
  --build-type TYPE                  CMake build type (default: Release)
  --build-jobs N                     Build jobs (default: 2)
  --disable-datalayers 0|1           Pass to builder (default: 1)
  --skip-dashboard 0|1               Pass to builder (default: 0)
  --dashboard-mode MODE              auto|local|release|skip (default: auto)
  --backup-root PATH                 Backup root (default: /opt/neuron/backups)
  --dirty-repo-fallback 0|1         Auto-switch source dir when git tree is dirty (default: 1)

Remote backend-stub options (default enabled):
  --enable-remote-stub 0|1            1 to auto-setup backend-stub service (default: 1)
  --enable-remote-ui-proxy 0|1        1 to expose merged UI+remote API via nginx (default: 1)
  --remote-ui-proxy-port PORT         nginx listen port for merged UI/API (default: 7002)
  --remote-stub-service-name NAME    systemd unit (default: neuron-remote-backend-stub)
  --remote-stub-host HOST            bind host (default: 0.0.0.0)
  --remote-stub-port PORT            bind port (default: 18080)
  --remote-state-dir PATH            profile state dir (default: /var/lib/neuron/remote-control)
  --remote-env-file PATH             env file path (default: /etc/neuron/remote-control.env)
  --remote-venv-dir PATH             python venv path for backend-stub (default: /opt/neuron/venvs/remote-backend-stub)
  --remote-neuron-base-url URL       local Neuron API URL (default: http://127.0.0.1:7000)
  --remote-neuron-token TOKEN        local Neuron API token
  --remote-gateway-id ID             SA gateway id for bootstrap profile
  --remote-control-server-url URL    SA reverse-channel URL (wss://...)
  --remote-auth-mode MODE            mtls|mtls_hmac (default: mtls)
  --remote-heartbeat-sec N           heartbeat seconds (default: 20)
  --remote-reconnect-sec N           reconnect seconds (default: 3)
  --remote-dryrun-default true|false dryRunDefault value (default: true)
  --remote-hmac-secret SECRET        HMAC secret (needed for mtls_hmac)

Examples:
  bash scripts/upgrade-cm4-native-safe-remote.sh \
    --repo https://github.com/<owner>/<repo>.git \
    --branch main
HELP
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo) REPO_URL="${2:-}"; shift 2 ;;
      --branch) REPO_BRANCH="${2:-}"; shift 2 ;;
      --install-root) INSTALL_ROOT="${2:-}"; shift 2 ;;
      --src-dir-name) SRC_DIR_NAME="${2:-}"; shift 2 ;;
      --build-dir) BUILD_DIR="${2:-}"; shift 2 ;;
      --service-name) SERVICE_NAME="${2:-}"; shift 2 ;;
      --build-type) BUILD_TYPE="${2:-}"; shift 2 ;;
      --build-jobs) BUILD_JOBS="${2:-}"; shift 2 ;;
      --disable-datalayers) DISABLE_DATALAYERS="${2:-}"; shift 2 ;;
      --skip-dashboard) SKIP_DASHBOARD="${2:-}"; shift 2 ;;
      --dashboard-mode) DASHBOARD_MODE="${2:-}"; shift 2 ;;
      --enable-remote-stub) ENABLE_REMOTE_STUB="${2:-}"; shift 2 ;;
      --enable-remote-ui-proxy) ENABLE_REMOTE_UI_PROXY="${2:-}"; shift 2 ;;
      --remote-ui-proxy-port) REMOTE_UI_PROXY_PORT="${2:-}"; shift 2 ;;
      --backup-root) BACKUP_ROOT="${2:-}"; shift 2 ;;
      --dirty-repo-fallback) DIRTY_REPO_FALLBACK="${2:-}"; shift 2 ;;
      --remote-stub-service-name) REMOTE_STUB_SERVICE_NAME="${2:-}"; shift 2 ;;
      --remote-stub-host) REMOTE_STUB_HOST="${2:-}"; shift 2 ;;
      --remote-stub-port) REMOTE_STUB_PORT="${2:-}"; shift 2 ;;
      --remote-state-dir) REMOTE_STATE_DIR="${2:-}"; shift 2 ;;
      --remote-env-file) REMOTE_ENV_FILE="${2:-}"; shift 2 ;;
      --remote-venv-dir) REMOTE_VENV_DIR="${2:-}"; shift 2 ;;
      --remote-neuron-base-url) REMOTE_NEURON_BASE_URL="${2:-}"; shift 2 ;;
      --remote-neuron-token) REMOTE_NEURON_TOKEN="${2:-}"; shift 2 ;;
      --remote-gateway-id) REMOTE_GATEWAY_ID="${2:-}"; shift 2 ;;
      --remote-control-server-url) REMOTE_CONTROL_SERVER_URL="${2:-}"; shift 2 ;;
      --remote-auth-mode) REMOTE_AUTH_MODE="${2:-}"; shift 2 ;;
      --remote-heartbeat-sec) REMOTE_HEARTBEAT_SEC="${2:-}"; shift 2 ;;
      --remote-reconnect-sec) REMOTE_RECONNECT_SEC="${2:-}"; shift 2 ;;
      --remote-dryrun-default) REMOTE_DRYRUN_DEFAULT="${2:-}"; shift 2 ;;
      --remote-hmac-secret) REMOTE_HMAC_SECRET="${2:-}"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
  done
}

validate_inputs() {
  if [[ -z "${REPO_URL}" ]]; then
    echo "ERROR: --repo is required" >&2
    exit 1
  fi
  if [[ "${ENABLE_REMOTE_STUB}" != "0" && "${ENABLE_REMOTE_STUB}" != "1" ]]; then
    echo "ERROR: --enable-remote-stub must be 0 or 1" >&2
    exit 1
  fi
  if [[ "${ENABLE_REMOTE_UI_PROXY}" != "0" && "${ENABLE_REMOTE_UI_PROXY}" != "1" ]]; then
    echo "ERROR: --enable-remote-ui-proxy must be 0 or 1" >&2
    exit 1
  fi
  if [[ "${ENABLE_REMOTE_UI_PROXY}" == "1" && "${ENABLE_REMOTE_STUB}" != "1" ]]; then
    echo "ERROR: --enable-remote-ui-proxy=1 requires --enable-remote-stub=1" >&2
    exit 1
  fi
  if [[ "${DIRTY_REPO_FALLBACK}" != "0" && "${DIRTY_REPO_FALLBACK}" != "1" ]]; then
    echo "ERROR: --dirty-repo-fallback must be 0 or 1" >&2
    exit 1
  fi
  if [[ "${ENABLE_REMOTE_STUB}" == "1" && "${REMOTE_AUTH_MODE}" != "mtls" && "${REMOTE_AUTH_MODE}" != "mtls_hmac" ]]; then
    echo "ERROR: --remote-auth-mode must be mtls or mtls_hmac" >&2
    exit 1
  fi
  if [[ "${ENABLE_REMOTE_STUB}" == "1" && "${REMOTE_AUTH_MODE}" == "mtls_hmac" && -z "${REMOTE_HMAC_SECRET}" ]]; then
    echo "ERROR: --remote-hmac-secret is required when --remote-auth-mode=mtls_hmac" >&2
    exit 1
  fi
}

stop_services_if_running() {
  if [[ "${HAS_SYSTEMCTL}" != "1" ]]; then
    return
  fi
  if ${SUDO} systemctl list-unit-files | rg -q "^${SERVICE_NAME}\\.service"; then
    if ${SUDO} systemctl is-active --quiet "${SERVICE_NAME}"; then
      echo "==> Stopping ${SERVICE_NAME}"
      ${SUDO} systemctl stop "${SERVICE_NAME}"
    fi
  fi

  if [[ "${ENABLE_REMOTE_STUB}" == "1" ]] && ${SUDO} systemctl list-unit-files | rg -q "^${REMOTE_STUB_SERVICE_NAME}\\.service"; then
    if ${SUDO} systemctl is-active --quiet "${REMOTE_STUB_SERVICE_NAME}"; then
      echo "==> Stopping ${REMOTE_STUB_SERVICE_NAME}"
      ${SUDO} systemctl stop "${REMOTE_STUB_SERVICE_NAME}"
    fi
  fi
}

backup_runtime_data() {
  local src_path="${INSTALL_ROOT}/${SRC_DIR_NAME}"
  local work_dir="${src_path}/${BUILD_DIR}"
  local config_dir="${work_dir}/config"
  local profile_in_repo="${src_path}/scripts/neuron-remote-control/backend-stub/data/connection-profile.json"
  local profile_secret_in_repo="${src_path}/scripts/neuron-remote-control/backend-stub/data/connection-profile.secret"

  BACKUP_LABEL="$(date +%Y%m%d-%H%M%S)"
  BACKUP_PATH="${BACKUP_ROOT}/${BACKUP_LABEL}"

  echo "==> Backing up runtime data to ${BACKUP_PATH}"
  ${SUDO} mkdir -p "${BACKUP_PATH}"

  if [[ -d "${config_dir}" ]]; then
    ${SUDO} cp -a "${config_dir}" "${BACKUP_PATH}/config"
  fi
  if [[ -f "${work_dir}/neuron.json" ]]; then
    ${SUDO} cp -a "${work_dir}/neuron.json" "${BACKUP_PATH}/neuron.json"
  fi
  if [[ "${ENABLE_REMOTE_STUB}" == "1" && -f "${profile_in_repo}" ]]; then
    ${SUDO} cp -a "${profile_in_repo}" "${BACKUP_PATH}/connection-profile.json"
  fi
  if [[ "${ENABLE_REMOTE_STUB}" == "1" && -f "${profile_secret_in_repo}" ]]; then
    ${SUDO} cp -a "${profile_secret_in_repo}" "${BACKUP_PATH}/connection-profile.secret"
  fi
}

run_upgrade_build() {
  local installer="${INSTALL_ROOT}/${SRC_DIR_NAME}/scripts/install-cm4-native-remote.sh"
  local temp_installer=""
  local enable_service_args=()
  local src_path="${INSTALL_ROOT}/${SRC_DIR_NAME}"
  local build_path="${src_path}/${BUILD_DIR}"
  local installer_help=""
  local supports_dashboard_mode=0
  local run_log=""
  local ts=""

  if [[ ! -f "${installer}" ]]; then
    installer="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/install-cm4-native-remote.sh"
  fi
  if [[ ! -f "${installer}" ]]; then
    if command -v curl >/dev/null 2>&1; then
      local repo_path
      repo_path="$(printf '%s' "${REPO_URL}" | sed -E 's#^https?://github.com/##; s#\.git$##')"
      temp_installer="/tmp/install-cm4-native-remote.sh.$$"
      echo "==> Fetching installer from GitHub"
      curl -fsSL "https://raw.githubusercontent.com/${repo_path}/${REPO_BRANCH}/scripts/install-cm4-native-remote.sh" -o "${temp_installer}"
      chmod +x "${temp_installer}"
      installer="${temp_installer}"
    else
      echo "ERROR: Cannot find install-cm4-native-remote.sh and curl is unavailable" >&2
      exit 1
    fi
  fi

  if [[ "${HAS_SYSTEMCTL}" == "1" ]]; then
    enable_service_args=(--enable-service --service-name "${SERVICE_NAME}")
  else
    echo "==> systemctl not found, skip service management during upgrade"
  fi

  # Avoid stale CMake cache path mismatch when source path changes.
  if [[ -f "${build_path}/CMakeCache.txt" ]]; then
    echo "==> Removing stale CMake cache in ${build_path}"
    rm -f "${build_path}/CMakeCache.txt"
    rm -rf "${build_path}/CMakeFiles"
  fi

  installer_help="$(bash "${installer}" --help 2>&1 || true)"
  if printf '%s' "${installer_help}" | rg -q -- '--dashboard-mode'; then
    supports_dashboard_mode=1
  else
    echo "==> Installer has no --dashboard-mode support, skipping that option"
  fi

  run_log="/tmp/neuron-upgrade-install.$$.log"

  echo "==> Upgrading Neuron source + build"
  if [[ "${supports_dashboard_mode}" == "1" ]]; then
    bash "${installer}" \
      --repo "${REPO_URL}" \
      --branch "${REPO_BRANCH}" \
      --install-root "${INSTALL_ROOT}" \
      --src-dir-name "${SRC_DIR_NAME}" \
      --build-dir "${BUILD_DIR}" \
      --build-type "${BUILD_TYPE}" \
      --build-jobs "${BUILD_JOBS}" \
      --disable-datalayers "${DISABLE_DATALAYERS}" \
      --skip-dashboard "${SKIP_DASHBOARD}" \
      --dashboard-mode "${DASHBOARD_MODE}" \
      "${enable_service_args[@]}" \
      2>&1 | tee "${run_log}"
  else
    bash "${installer}" \
      --repo "${REPO_URL}" \
      --branch "${REPO_BRANCH}" \
      --install-root "${INSTALL_ROOT}" \
      --src-dir-name "${SRC_DIR_NAME}" \
      --build-dir "${BUILD_DIR}" \
      --build-type "${BUILD_TYPE}" \
      --build-jobs "${BUILD_JOBS}" \
      --disable-datalayers "${DISABLE_DATALAYERS}" \
      --skip-dashboard "${SKIP_DASHBOARD}" \
      "${enable_service_args[@]}" \
      2>&1 | tee "${run_log}"
  fi
  local run_rc=${PIPESTATUS[0]}

  if [[ "${run_rc}" -ne 0 && "${DIRTY_REPO_FALLBACK}" == "1" ]] && \
     rg -q "would be overwritten by merge|Please commit your changes or stash them" "${run_log}"; then
    ts="$(date +%Y%m%d-%H%M%S)"
    SRC_DIR_NAME="${SRC_DIR_NAME}-next-${ts}"
    src_path="${INSTALL_ROOT}/${SRC_DIR_NAME}"
    build_path="${src_path}/${BUILD_DIR}"
    echo "==> Dirty git tree detected, switching source dir to ${SRC_DIR_NAME}"
    if [[ "${supports_dashboard_mode}" == "1" ]]; then
      bash "${installer}" \
        --repo "${REPO_URL}" \
        --branch "${REPO_BRANCH}" \
        --install-root "${INSTALL_ROOT}" \
        --src-dir-name "${SRC_DIR_NAME}" \
        --build-dir "${BUILD_DIR}" \
        --build-type "${BUILD_TYPE}" \
        --build-jobs "${BUILD_JOBS}" \
        --disable-datalayers "${DISABLE_DATALAYERS}" \
        --skip-dashboard "${SKIP_DASHBOARD}" \
        --dashboard-mode "${DASHBOARD_MODE}" \
        "${enable_service_args[@]}"
    else
      bash "${installer}" \
        --repo "${REPO_URL}" \
        --branch "${REPO_BRANCH}" \
        --install-root "${INSTALL_ROOT}" \
        --src-dir-name "${SRC_DIR_NAME}" \
        --build-dir "${BUILD_DIR}" \
        --build-type "${BUILD_TYPE}" \
        --build-jobs "${BUILD_JOBS}" \
        --disable-datalayers "${DISABLE_DATALAYERS}" \
        --skip-dashboard "${SKIP_DASHBOARD}" \
        "${enable_service_args[@]}"
    fi
  elif [[ "${run_rc}" -ne 0 ]] && rg -q "CMakeCache.txt directory .* /src/build-native-cm4|does not match the source \"/src/CMakeLists.txt\"" "${run_log}"; then
    ts="$(date +%Y%m%d-%H%M%S)"
    BUILD_DIR="${BUILD_DIR}-${ts}"
    build_path="${INSTALL_ROOT}/${SRC_DIR_NAME}/${BUILD_DIR}"
    echo "==> Stale /src CMake cache detected, switching build dir to ${BUILD_DIR}"
    if [[ "${supports_dashboard_mode}" == "1" ]]; then
      bash "${installer}" \
        --repo "${REPO_URL}" \
        --branch "${REPO_BRANCH}" \
        --install-root "${INSTALL_ROOT}" \
        --src-dir-name "${SRC_DIR_NAME}" \
        --build-dir "${BUILD_DIR}" \
        --build-type "${BUILD_TYPE}" \
        --build-jobs "${BUILD_JOBS}" \
        --disable-datalayers "${DISABLE_DATALAYERS}" \
        --skip-dashboard "${SKIP_DASHBOARD}" \
        --dashboard-mode "${DASHBOARD_MODE}" \
        "${enable_service_args[@]}"
    else
      bash "${installer}" \
        --repo "${REPO_URL}" \
        --branch "${REPO_BRANCH}" \
        --install-root "${INSTALL_ROOT}" \
        --src-dir-name "${SRC_DIR_NAME}" \
        --build-dir "${BUILD_DIR}" \
        --build-type "${BUILD_TYPE}" \
        --build-jobs "${BUILD_JOBS}" \
        --disable-datalayers "${DISABLE_DATALAYERS}" \
        --skip-dashboard "${SKIP_DASHBOARD}" \
        "${enable_service_args[@]}"
    fi
  elif [[ "${run_rc}" -ne 0 ]]; then
    echo "ERROR: upgrade build failed (log: ${run_log})" >&2
    exit "${run_rc}"
  fi

  rm -f "${run_log}"

  # Re-apply runtime cache cleanup if new source dir already had stale cache.
  if [[ -f "${build_path}/CMakeCache.txt" ]]; then
    if rg -q "/src/" "${build_path}/CMakeCache.txt"; then
      echo "==> Detected stale /src cache, regenerating build cache"
      rm -f "${build_path}/CMakeCache.txt"
      rm -rf "${build_path}/CMakeFiles"
    fi
  fi

  if [[ -n "${temp_installer}" ]]; then
    rm -f "${temp_installer}"
  fi
}

restore_runtime_data() {
  local src_path="${INSTALL_ROOT}/${SRC_DIR_NAME}"
  local work_dir="${src_path}/${BUILD_DIR}"

  if [[ -d "${BACKUP_PATH}/config" ]]; then
    echo "==> Restoring Neuron config directory"
    ${SUDO} mkdir -p "${work_dir}"
    ${SUDO} rm -rf "${work_dir}/config"
    ${SUDO} cp -a "${BACKUP_PATH}/config" "${work_dir}/config"
  fi
  if [[ -f "${BACKUP_PATH}/neuron.json" ]]; then
    ${SUDO} cp -a "${BACKUP_PATH}/neuron.json" "${work_dir}/neuron.json"
  fi
}

setup_remote_stub_profile() {
  local profile_path="${REMOTE_STATE_DIR}/connection-profile.json"
  local secret_path="${REMOTE_STATE_DIR}/connection-profile.secret"
  local updated_at
  updated_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  echo "==> Preparing persistent backend-stub state at ${REMOTE_STATE_DIR}"
  ${SUDO} mkdir -p "${REMOTE_STATE_DIR}"

  if [[ -f "${BACKUP_PATH}/connection-profile.json" && ! -f "${profile_path}" ]]; then
    ${SUDO} cp -a "${BACKUP_PATH}/connection-profile.json" "${profile_path}"
  fi
  if [[ -f "${BACKUP_PATH}/connection-profile.secret" && ! -f "${secret_path}" ]]; then
    ${SUDO} cp -a "${BACKUP_PATH}/connection-profile.secret" "${secret_path}"
  fi

  if [[ ! -f "${profile_path}" ]]; then
    ${SUDO} tee "${profile_path}" >/dev/null <<EOF
{
  "enabled": false,
  "gatewayId": "${REMOTE_GATEWAY_ID}",
  "controlServerUrl": "${REMOTE_CONTROL_SERVER_URL}",
  "authMode": "${REMOTE_AUTH_MODE}",
  "hmacEnabled": $([[ "${REMOTE_AUTH_MODE}" == "mtls_hmac" ]] && echo "true" || echo "false"),
  "heartbeatSec": ${REMOTE_HEARTBEAT_SEC},
  "reconnectSec": ${REMOTE_RECONNECT_SEC},
  "dryRunDefault": ${REMOTE_DRYRUN_DEFAULT},
  "description": "seeded by safe-upgrade",
  "updatedAt": "${updated_at}"
}
EOF
  fi

  if [[ -n "${REMOTE_HMAC_SECRET}" ]]; then
    printf '%s' "${REMOTE_HMAC_SECRET}" | ${SUDO} tee "${secret_path}" >/dev/null
  fi
}

write_remote_stub_env() {
  local src_path="${INSTALL_ROOT}/${SRC_DIR_NAME}"
  local profile_path="${REMOTE_STATE_DIR}/connection-profile.json"
  local secret_path="${REMOTE_STATE_DIR}/connection-profile.secret"

  echo "==> Writing backend-stub env file ${REMOTE_ENV_FILE}"
  ${SUDO} mkdir -p "$(dirname "${REMOTE_ENV_FILE}")"
  ${SUDO} tee "${REMOTE_ENV_FILE}" >/dev/null <<EOF
PYTHONPATH=${src_path}/scripts/neuron-remote-control/backend-stub
REMOTE_PROFILE_PATH=${profile_path}
REMOTE_CONNECTION_SCHEMA=${src_path}/scripts/neuron-remote-control/contracts/connection-profile.schema.json
REMOTE_AGENT_SCRIPT=${src_path}/scripts/neuron-remote-control/agent/gateway_agent.py
REMOTE_SCHEMA_PATH=${src_path}/scripts/neuron-remote-control/contracts/command-envelope.schema.json
REMOTE_NEURON_BASE_URL=${REMOTE_NEURON_BASE_URL}
REMOTE_NEURON_TOKEN=${REMOTE_NEURON_TOKEN}
REMOTE_PROFILE_SECRET_PATH=${secret_path}
EOF
}

install_backend_stub_deps() {
  local src_path="${INSTALL_ROOT}/${SRC_DIR_NAME}"
  local req_file="${src_path}/scripts/neuron-remote-control/backend-stub/requirements.txt"
  local venv_python="${REMOTE_VENV_DIR}/bin/python3"
  local py_mm=""

  if ! command -v python3 >/dev/null 2>&1; then
    ${SUDO} apt-get update -qq
    ${SUDO} apt-get install -y -qq python3 python3-venv python3-pip
  fi
  if ! python3 -m venv -h >/dev/null 2>&1; then
    ${SUDO} apt-get update -qq
    ${SUDO} apt-get install -y -qq python3-venv
  fi
  if ! python3 -m pip --version >/dev/null 2>&1; then
    ${SUDO} apt-get update -qq
    ${SUDO} apt-get install -y -qq python3-pip
  fi
  if [[ ! -x "${venv_python}" ]]; then
    ${SUDO} mkdir -p "$(dirname "${REMOTE_VENV_DIR}")"
    if ! ${SUDO} python3 -m venv "${REMOTE_VENV_DIR}"; then
      py_mm="$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
      ${SUDO} apt-get update -qq
      ${SUDO} apt-get install -y -qq "python${py_mm}-venv" python3-venv
      ${SUDO} python3 -m venv "${REMOTE_VENV_DIR}"
    fi
  fi
  if ! ${SUDO} "${venv_python}" -m pip --version >/dev/null 2>&1; then
    py_mm="$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
    ${SUDO} apt-get update -qq
    ${SUDO} apt-get install -y -qq "python${py_mm}-venv" python3-venv python3-pip
    ${SUDO} "${venv_python}" -m ensurepip --upgrade >/dev/null 2>&1 || true
    if ! ${SUDO} "${venv_python}" -m pip --version >/dev/null 2>&1; then
      ${SUDO} rm -rf "${REMOTE_VENV_DIR}"
      ${SUDO} python3 -m venv "${REMOTE_VENV_DIR}"
    fi
  fi
  ${SUDO} "${venv_python}" -m pip install --upgrade pip >/dev/null
  ${SUDO} "${venv_python}" -m pip install -r "${req_file}"
}

write_remote_stub_service() {
  local src_path="${INSTALL_ROOT}/${SRC_DIR_NAME}"
  local service_file="/etc/systemd/system/${REMOTE_STUB_SERVICE_NAME}.service"

  echo "==> Writing ${REMOTE_STUB_SERVICE_NAME}.service"
  ${SUDO} tee "${service_file}" >/dev/null <<EOF
[Unit]
Description=Neuron Remote Backend Stub
After=network.target ${SERVICE_NAME}.service
Wants=${SERVICE_NAME}.service

[Service]
Type=simple
EnvironmentFile=${REMOTE_ENV_FILE}
WorkingDirectory=${src_path}
ExecStart=${REMOTE_VENV_DIR}/bin/python3 -m uvicorn app.main:app --app-dir scripts/neuron-remote-control/backend-stub --host ${REMOTE_STUB_HOST} --port ${REMOTE_STUB_PORT}
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
}

setup_remote_ui_proxy() {
  local site_file="/etc/nginx/sites-available/neuron-remote-ui.conf"
  local enabled_file="/etc/nginx/sites-enabled/neuron-remote-ui.conf"

  if [[ "${HAS_SYSTEMCTL}" != "1" ]]; then
    echo "==> systemctl not found, skip remote UI proxy setup"
    return
  fi

  if ! command -v nginx >/dev/null 2>&1; then
    echo "==> Installing nginx for unified UI/API endpoint"
    ${SUDO} apt-get update -qq
    ${SUDO} apt-get install -y -qq nginx
  fi

  echo "==> Writing nginx site for remote-control UI API bridge"
  ${SUDO} tee "${site_file}" >/dev/null <<EOF
server {
    listen ${REMOTE_UI_PROXY_PORT};
    server_name _;

    location /api/v2/remote/ {
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_pass http://127.0.0.1:${REMOTE_STUB_PORT};
    }

    location / {
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_pass http://127.0.0.1:7001;
    }
}
EOF

  ${SUDO} ln -sf "${site_file}" "${enabled_file}"
  if [[ -e /etc/nginx/sites-enabled/default ]]; then
    ${SUDO} rm -f /etc/nginx/sites-enabled/default
  fi
  ${SUDO} nginx -t
  ${SUDO} systemctl enable --now nginx
  ${SUDO} systemctl reload nginx
}

start_services() {
  if [[ "${HAS_SYSTEMCTL}" != "1" ]]; then
    return
  fi
  ${SUDO} systemctl daemon-reload
  ${SUDO} systemctl enable --now "${SERVICE_NAME}"
  if [[ "${ENABLE_REMOTE_STUB}" == "1" ]]; then
    ${SUDO} systemctl enable --now "${REMOTE_STUB_SERVICE_NAME}"
  fi
}

print_summary() {
  echo
  echo "==> Safe upgrade completed"
  echo "Backup: ${BACKUP_PATH}"
  echo "Neuron service: ${SERVICE_NAME}"
  if [[ "${ENABLE_REMOTE_STUB}" == "1" ]]; then
    echo "Remote stub service: ${REMOTE_STUB_SERVICE_NAME}"
    echo "Remote API: http://${REMOTE_STUB_HOST}:${REMOTE_STUB_PORT}/api/v2/remote/connection"
    if [[ "${ENABLE_REMOTE_UI_PROXY}" == "1" ]]; then
      echo "Merged UI+Remote endpoint: http://127.0.0.1:${REMOTE_UI_PROXY_PORT}/web/#/login"
    fi
  fi
  echo
  echo "Quick check:"
  if [[ "${HAS_SYSTEMCTL}" == "1" ]]; then
    echo "  sudo systemctl status ${SERVICE_NAME}"
  else
    echo "  systemctl not available in this environment"
  fi
  if [[ "${ENABLE_REMOTE_STUB}" == "1" ]]; then
    if [[ "${HAS_SYSTEMCTL}" == "1" ]]; then
      echo "  sudo systemctl status ${REMOTE_STUB_SERVICE_NAME}"
    fi
    echo "  curl -s http://127.0.0.1:${REMOTE_STUB_PORT}/api/v2/remote/connection"
    if [[ "${ENABLE_REMOTE_UI_PROXY}" == "1" ]]; then
      echo "  curl -s -i http://127.0.0.1:${REMOTE_UI_PROXY_PORT}/api/v2/remote/connection/status"
    fi
  fi
}

main() {
  parse_args "$@"
  validate_inputs
  stop_services_if_running
  backup_runtime_data
  run_upgrade_build
  restore_runtime_data
  if [[ "${ENABLE_REMOTE_STUB}" == "1" ]]; then
    setup_remote_stub_profile
    write_remote_stub_env
    install_backend_stub_deps
    write_remote_stub_service
  fi
  start_services
  if [[ "${ENABLE_REMOTE_STUB}" == "1" && "${ENABLE_REMOTE_UI_PROXY}" == "1" ]]; then
    setup_remote_ui_proxy
  fi
  print_summary
}

main "$@"
