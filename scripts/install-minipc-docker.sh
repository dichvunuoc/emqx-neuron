#!/usr/bin/env bash
# One-shot mini PC install: Docker (if needed) + pull/load images + compose up (Neuron + remote stub).
#
# Examples:
#   curl -fsSL https://raw.githubusercontent.com/<owner>/<repo>/main/scripts/install-minipc-docker.sh | \
#     bash -s -- --neuron-image registry.example.com/neuron-full:1.0 --stub-image registry.example.com/neuron-remote-stub:1.0
#
# Env (optional):
#   INSTALL_DIR=/opt/neuron-minipc
#   SOURCE_BASE_URL=https://raw.githubusercontent.com/<owner>/<repo>/main/deploy/minipc
#   STACK_REGISTRY=registry.example.com/iot  STACK_TAG=1.0   # cùng tag cho neuron-full + neuron-remote-stub
#   STACK_IMAGE_TAR=/path/neuron-stack-1.0.tar   # Neuron + stub + Nginx (EXPORT_STACK_TAR=1 khi build)
#   IMAGE_TAR=/path/neuron.tar STUB_IMAGE_TAR=/path/stub.tar
#   SKIP_DOCKER_INSTALL=1
#   BUNDLE_DIR=/path/to/bundle  # thư mục chứa docker-compose.yml, nginx.conf, .env.example (offline/USB)
#
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/opt/neuron-minipc}"
SOURCE_BASE_URL="${SOURCE_BASE_URL:-}"
BUNDLE_DIR="${BUNDLE_DIR:-}"
NEURON_IMAGE="${NEURON_IMAGE:-}"
REMOTE_STUB_IMAGE="${REMOTE_STUB_IMAGE:-}"
STUB_IMAGE="${STUB_IMAGE:-}"
NGINX_IMAGE="${NGINX_IMAGE:-}"
SKIP_DOCKER_INSTALL="${SKIP_DOCKER_INSTALL:-0}"
SKIP_DOCKER_PULL="${SKIP_DOCKER_PULL:-}"
VERIFY_BUNDLE="${VERIFY_BUNDLE:-1}"
HEALTH_TIMEOUT="${HEALTH_TIMEOUT:-180}"
ALLOW_ARCH_MISMATCH="${ALLOW_ARCH_MISMATCH:-0}"
KEEP_EXISTING_IMAGE_TAGS="${KEEP_EXISTING_IMAGE_TAGS:-0}"
NEURON_CONFIG_CHANGED=0

SUDO=""
if [[ "${EUID}" -ne 0 ]]; then
  SUDO="sudo"
fi

DKR() {
  if [[ "${EUID}" -eq 0 ]] || groups | grep -q '\bdocker\b'; then
    docker "$@"
  else
    sudo docker "$@"
  fi
}

DC() {
  if [[ "${EUID}" -eq 0 ]] || groups | grep -q '\bdocker\b'; then
    docker compose "$@"
  else
    sudo docker compose "$@"
  fi
}

# The host config mount hides /opt/neuron/config from the image. Seed every missing
# config/migration file before first start, while preserving existing runtime config.
minipc_seed_config_from_image() {
  local cfg_dir="${INSTALL_DIR}/data/config"
  local tmp_dir
  local container_id
  local src
  local rel
  local dst

  tmp_dir="$(mktemp -d)"
  container_id="$(DKR create "${NEURON_IMAGE}")"
  if ! DKR cp "${container_id}:/opt/neuron/config/." "${tmp_dir}/"; then
    DKR rm -f "${container_id}" >/dev/null 2>&1 || true
    ${SUDO} rm -rf "${tmp_dir}"
    echo "ERROR: không đọc được /opt/neuron/config từ image ${NEURON_IMAGE}." >&2
    exit 1
  fi
  DKR rm -f "${container_id}" >/dev/null

  while IFS= read -r -d '' src; do
    rel="${src#"${tmp_dir}"/}"
    dst="${cfg_dir}/${rel}"
    if [[ ! -f "${dst}" ]]; then
      echo ">> Seed config/${rel} từ image"
      ${SUDO} mkdir -p "$(dirname "${dst}")"
      ${SUDO} install -m 0644 "${src}" "${dst}"
      NEURON_CONFIG_CHANGED=1
    fi
  done < <(find "${tmp_dir}" -type f -print0)

  # Existing installations keep their config, but refresh the plugin catalog when
  # the newly installed image adds the S7 drivers.
  if [[ -f "${tmp_dir}/default_plugins.json" ]] && \
     grep -q 'libplugin-s7comm\.so' "${tmp_dir}/default_plugins.json" 2>/dev/null && \
     ! grep -q 'libplugin-s7comm\.so' "${cfg_dir}/default_plugins.json" 2>/dev/null; then
    echo ">> Cập nhật config/default_plugins.json để nhận plugin S7 mới"
    ${SUDO} install -m 0644 "${tmp_dir}/default_plugins.json" "${cfg_dir}/default_plugins.json"
    NEURON_CONFIG_CHANGED=1
  fi

  ${SUDO} rm -rf "${tmp_dir}"
}

minipc_env_value() {
  local file="$1"
  local key="$2"
  awk -v key="${key}" 'index($0, key "=") == 1 { value=substr($0, length(key) + 2) } END { print value }' "${file}"
}

minipc_verify_bundle() {
  if [[ -z "${BUNDLE_DIR}" || "${VERIFY_BUNDLE}" == "0" ]]; then
    return 0
  fi
  if [[ ! -f "${BUNDLE_DIR}/SHA256SUMS" ]]; then
    echo "ERROR: bundle thiếu SHA256SUMS. Dùng VERIFY_BUNDLE=0 chỉ khi bạn chủ động chấp nhận bỏ kiểm tra." >&2
    exit 1
  fi
  if ! command -v sha256sum >/dev/null 2>&1; then
    echo "ERROR: cần sha256sum để kiểm tra bundle. Dùng VERIFY_BUNDLE=0 chỉ khi bạn chấp nhận bỏ kiểm tra." >&2
    exit 1
  fi
  echo ">> Kiểm tra SHA-256 của bộ cài"
  ( cd "${BUNDLE_DIR}" && sha256sum -c SHA256SUMS )
}

minipc_verify_stack_tar_is_listed() {
  local tar_dir
  local tar_entry
  if [[ -z "${BUNDLE_DIR}" || "${VERIFY_BUNDLE}" == "0" || -z "${STACK_IMAGE_TAR:-}" ]]; then
    return 0
  fi
  tar_dir="$(cd "$(dirname "${STACK_IMAGE_TAR}")" && pwd)"
  if [[ "${tar_dir}" != "${BUNDLE_DIR}" ]]; then
    echo "ERROR: STACK_IMAGE_TAR nằm ngoài bundle nên không được SHA256SUMS bảo vệ." >&2
    echo "Hãy chép tar vào bundle và tạo lại SHA256SUMS, hoặc đặt VERIFY_BUNDLE=0 nếu bạn tự xác minh file." >&2
    exit 1
  fi
  tar_entry="./$(basename "${STACK_IMAGE_TAR}")"
  if ! awk '{ print $2 }' "${BUNDLE_DIR}/SHA256SUMS" | grep -Fqx -- "${tar_entry}"; then
    echo "ERROR: ${tar_entry} không có trong SHA256SUMS; từ chối nạp image tar chưa được xác minh." >&2
    exit 1
  fi
}

minipc_update_image_env() {
  local env_file="$1"
  local tmp_file
  tmp_file="$(mktemp)"
  awk \
    -v neuron="${NEURON_IMAGE}" \
    -v stub="${REMOTE_STUB_IMAGE}" \
    -v nginx="${NGINX_IMAGE}" '
      /^NEURON_IMAGE=/ {
        if (!seen_neuron++) print "NEURON_IMAGE=" neuron
        next
      }
      /^REMOTE_STUB_IMAGE=/ {
        if (!seen_stub++) print "REMOTE_STUB_IMAGE=" stub
        next
      }
      /^NGINX_IMAGE=/ {
        if (!seen_nginx++) print "NGINX_IMAGE=" nginx
        next
      }
      { print }
      END {
        if (!seen_neuron) print "NEURON_IMAGE=" neuron
        if (!seen_stub) print "REMOTE_STUB_IMAGE=" stub
        if (!seen_nginx) print "NGINX_IMAGE=" nginx
      }
    ' "${env_file}" > "${tmp_file}"
  ${SUDO} install -m 0600 "${tmp_file}" "${env_file}"
  rm -f "${tmp_file}"
}

minipc_resolve_bundle_defaults() {
  local env_file="${BUNDLE_DIR}/.env.example"
  local candidate=""
  local -a stack_tars=()

  if [[ -z "${NEURON_IMAGE}" ]]; then
    candidate="$(minipc_env_value "${env_file}" NEURON_IMAGE)"
    if [[ -n "${candidate}" && "${candidate}" != registry.example.com/* ]]; then
      NEURON_IMAGE="${candidate}"
    fi
  fi
  if [[ -z "${REMOTE_STUB_IMAGE}" ]]; then
    candidate="$(minipc_env_value "${env_file}" REMOTE_STUB_IMAGE)"
    if [[ -n "${candidate}" && "${candidate}" != registry.example.com/* ]]; then
      REMOTE_STUB_IMAGE="${candidate}"
    fi
  fi
  if [[ -z "${NGINX_IMAGE}" ]]; then
    NGINX_IMAGE="$(minipc_env_value "${env_file}" NGINX_IMAGE)"
  fi

  if [[ -z "${STACK_IMAGE_TAR:-}" ]]; then
    while IFS= read -r -d '' candidate; do
      stack_tars+=("${candidate}")
    done < <(find "${BUNDLE_DIR}" -maxdepth 1 -type f -name 'neuron-stack-*.tar' -print0)
    if [[ ${#stack_tars[@]} -eq 1 ]]; then
      STACK_IMAGE_TAR="${stack_tars[0]}"
      echo ">> Tự nhận image tar: ${STACK_IMAGE_TAR}"
    elif [[ ${#stack_tars[@]} -gt 1 ]]; then
      echo "ERROR: bundle có nhiều neuron-stack-*.tar; hãy đặt STACK_IMAGE_TAR rõ ràng." >&2
      exit 1
    fi
  fi
}

minipc_normalize_arch() {
  case "$1" in
    aarch64|arm64) echo arm64 ;;
    x86_64|amd64) echo amd64 ;;
    armv7l|armhf) echo arm ;;
    *) echo "$1" ;;
  esac
}

minipc_require_image() {
  local image="$1"
  local host_arch
  local image_arch
  if ! DKR image inspect "${image}" >/dev/null 2>&1; then
    echo "ERROR: thiếu image ${image}. Bundle/tar không khớp hoặc pull thất bại." >&2
    exit 1
  fi
  if [[ "${ALLOW_ARCH_MISMATCH}" == "1" ]]; then
    return 0
  fi
  host_arch="$(minipc_normalize_arch "$(uname -m)")"
  image_arch="$(minipc_normalize_arch "$(DKR image inspect --format '{{.Architecture}}' "${image}")")"
  if [[ "${host_arch}" != "${image_arch}" ]]; then
    echo "ERROR: image ${image} là ${image_arch}, máy hiện tại là ${host_arch}." >&2
    echo "Hãy dùng đúng bundle kiến trúc hoặc đặt ALLOW_ARCH_MISMATCH=1 nếu máy đã cấu hình giả lập." >&2
    exit 1
  fi
}

minipc_wait_healthy() {
  local container="$1"
  local label="$2"
  local deadline=$((SECONDS + HEALTH_TIMEOUT))
  local state=""
  echo ">> Chờ ${label} sẵn sàng (tối đa ${HEALTH_TIMEOUT}s)"
  while (( SECONDS < deadline )); do
    state="$(DKR inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "${container}" 2>/dev/null || true)"
    case "${state}" in
      healthy|running)
        echo ">> ${label}: ${state}"
        return 0
        ;;
      unhealthy|exited|dead)
        break
        ;;
    esac
    sleep 2
  done
  echo "ERROR: ${label} chưa sẵn sàng (state=${state:-unknown})." >&2
  ( cd "${INSTALL_DIR}" && DC ps && DC logs --tail=80 ) >&2 || true
  exit 1
}

minipc_disable_native_neuron() {
  if ! command -v systemctl >/dev/null 2>&1; then
    return 0
  fi
  local frag
  frag="$(${SUDO} systemctl show -p FragmentPath --value neuron.service 2>/dev/null || true)"
  if [[ -z "${frag}" ]]; then
    return 0
  fi
  echo ">> Phát hiện neuron.service (Neuron native) — stop, disable, mask (chỉ chạy Neuron trong Docker)."
  ${SUDO} systemctl stop neuron.service 2>/dev/null || true
  ${SUDO} systemctl disable neuron.service 2>/dev/null || true
  ${SUDO} systemctl mask neuron.service 2>/dev/null || true
}

usage() {
  cat <<'HELP'
Usage:
  curl -fsSL <URL>/install-minipc-docker.sh | bash -s -- [options]

Options:
  --neuron-image TAG       Image for Neuron (required unless NEURON_IMAGE is set)
  --stub-image TAG         Image for remote backend stub (required unless REMOTE_STUB_IMAGE is set)
  --install-dir PATH       Install directory (default: /opt/neuron-minipc)
  --source-base-url URL    Raw GitHub base for deploy/minipc files (default: auto from INSTALL_SCRIPT_REPO)
  --bundle-dir PATH        Dùng file local (docker-compose.yml, nginx.conf, .env.example) thay vì curl
  --skip-docker-install    Do not run get.docker.com bootstrap

Env:
  INSTALL_SCRIPT_REPO   owner/repo for GitHub raw paths (default: emqx/neuron)
  INSTALL_SCRIPT_BRANCH branch name (default: main)
  STACK_REGISTRY        + STACK_TAG → tự set NEURON_IMAGE / REMOTE_STUB_IMAGE (nếu chưa truyền --neuron-image)
  IMAGE_TAR             docker load this tar for Neuron image (optional)
  STUB_IMAGE_TAR        docker load this tar for stub image (optional)
  BUNDLE_DIR            giống --bundle-dir
  SKIP_DOCKER_PULL=1    Không chạy docker pull (offline). Mặc định: tự bật nếu có STACK_IMAGE_TAR.
  VERIFY_BUNDLE=0       Bỏ kiểm tra SHA256SUMS (không khuyến nghị)
  HEALTH_TIMEOUT=180    Thời gian chờ 3 dịch vụ healthy
  KEEP_EXISTING_IMAGE_TAGS=1  Giữ ba image tag cũ khi chạy installer từ bundle mới
HELP
}

INSTALL_SCRIPT_REPO="${INSTALL_SCRIPT_REPO:-dichvunuoc/emqx-neuron}"
INSTALL_SCRIPT_BRANCH="${INSTALL_SCRIPT_BRANCH:-main}"
STACK_REGISTRY="${STACK_REGISTRY:-}"
STACK_TAG="${STACK_TAG:-latest}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --neuron-image)
      NEURON_IMAGE="${2:-}"
      shift 2
      ;;
    --stub-image)
      REMOTE_STUB_IMAGE="${2:-}"
      shift 2
      ;;
    --install-dir)
      INSTALL_DIR="${2:-}"
      shift 2
      ;;
    --source-base-url)
      SOURCE_BASE_URL="${2:-}"
      shift 2
      ;;
    --bundle-dir)
      BUNDLE_DIR="${2:-}"
      shift 2
      ;;
    --skip-docker-install)
      SKIP_DOCKER_INSTALL=1
      shift
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

if [[ -n "${BUNDLE_DIR}" ]]; then
  BUNDLE_DIR="$(cd "${BUNDLE_DIR}" && pwd)"
  for f in docker-compose.yml nginx.conf .env.example; do
    if [[ ! -f "${BUNDLE_DIR}/${f}" ]]; then
      echo "ERROR: --bundle-dir thiếu ${f} (${BUNDLE_DIR})" >&2
      exit 1
    fi
  done
  minipc_verify_bundle
  minipc_resolve_bundle_defaults
  minipc_verify_stack_tar_is_listed
elif [[ -z "${SOURCE_BASE_URL}" ]]; then
  SOURCE_BASE_URL="https://raw.githubusercontent.com/${INSTALL_SCRIPT_REPO}/${INSTALL_SCRIPT_BRANCH}/deploy/minipc"
fi

if [[ -n "${STACK_REGISTRY}" ]]; then
  NEURON_IMAGE="${NEURON_IMAGE:-${STACK_REGISTRY}/neuron-full:${STACK_TAG}}"
  REMOTE_STUB_IMAGE="${REMOTE_STUB_IMAGE:-${STUB_IMAGE:-${STACK_REGISTRY}/neuron-remote-stub:${STACK_TAG}}}"
fi
NGINX_IMAGE="${NGINX_IMAGE:-nginx:1.27-alpine}"

if [[ -z "${NEURON_IMAGE}" || -z "${REMOTE_STUB_IMAGE}" ]]; then
  echo "ERROR: set --neuron-image và --stub-image, hoặc STACK_REGISTRY (+ STACK_TAG), hoặc NEURON_IMAGE / REMOTE_STUB_IMAGE." >&2
  usage
  exit 1
fi

if [[ -z "${SKIP_DOCKER_PULL}" ]]; then
  if [[ -n "${STACK_IMAGE_TAR:-}" ]]; then
    SKIP_DOCKER_PULL=1
  else
    SKIP_DOCKER_PULL=0
  fi
fi

if command -v docker >/dev/null 2>&1; then
  echo ">> Docker already installed — skipping get.docker.com."
elif [[ "${SKIP_DOCKER_INSTALL}" == "1" ]]; then
  echo "ERROR: docker not found and SKIP_DOCKER_INSTALL=1." >&2
  exit 1
else
  echo ">> Installing Docker (get.docker.com)..."
  curl -fsSL https://get.docker.com | ${SUDO} sh
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker not found after install step." >&2
  exit 1
fi

if ! DC version >/dev/null 2>&1; then
  echo "ERROR: 'docker compose' plugin missing. Install Docker Engine with Compose v2." >&2
  exit 1
fi

echo ">> Preparing ${INSTALL_DIR}"
${SUDO} mkdir -p \
  "${INSTALL_DIR}/data/config" \
  "${INSTALL_DIR}/data/logs" \
  "${INSTALL_DIR}/data/persistence" \
  "${INSTALL_DIR}/data/remote-stub"

ENV_EXAMPLE_SRC=""
if [[ -n "${BUNDLE_DIR}" ]]; then
  echo ">> Copy compose + nginx từ bundle ${BUNDLE_DIR}"
  ${SUDO} install -m 0644 "${BUNDLE_DIR}/docker-compose.yml" "${INSTALL_DIR}/docker-compose.yml"
  ${SUDO} install -m 0644 "${BUNDLE_DIR}/nginx.conf" "${INSTALL_DIR}/nginx.conf"
  ENV_EXAMPLE_SRC="${BUNDLE_DIR}/.env.example"
else
  local_tmp="$(mktemp)"
  curl -fsSL "${SOURCE_BASE_URL}/docker-compose.yml" -o "${local_tmp}"
  ${SUDO} install -m 0644 "${local_tmp}" "${INSTALL_DIR}/docker-compose.yml"
  rm -f "${local_tmp}"
  local_tmp="$(mktemp)"
  curl -fsSL "${SOURCE_BASE_URL}/nginx.conf" -o "${local_tmp}"
  ${SUDO} install -m 0644 "${local_tmp}" "${INSTALL_DIR}/nginx.conf"
  rm -f "${local_tmp}"
  ENV_EXAMPLE_SRC="$(mktemp)"
  curl -fsSL "${SOURCE_BASE_URL}/.env.example" -o "${ENV_EXAMPLE_SRC}"
fi

if [[ -f "${INSTALL_DIR}/.env" ]]; then
  echo ">> Keeping existing ${INSTALL_DIR}/.env"
  if [[ -n "${BUNDLE_DIR}" && "${KEEP_EXISTING_IMAGE_TAGS}" != "1" ]]; then
    echo ">> Cập nhật ba image tag từ bundle mới; giữ nguyên token và các thiết lập khác"
    minipc_update_image_env "${INSTALL_DIR}/.env"
  fi
else
  sed \
    -e "s|^NEURON_IMAGE=.*|NEURON_IMAGE=${NEURON_IMAGE}|" \
    -e "s|^REMOTE_STUB_IMAGE=.*|REMOTE_STUB_IMAGE=${REMOTE_STUB_IMAGE}|" \
    -e "s|^NGINX_IMAGE=.*|NGINX_IMAGE=${NGINX_IMAGE}|" \
    "${ENV_EXAMPLE_SRC}" | ${SUDO} tee "${INSTALL_DIR}/.env" >/dev/null
  ${SUDO} chmod 0600 "${INSTALL_DIR}/.env"
fi

# Compose reads the installed .env. When re-running the installer, honor those
# persisted image tags so pull/inspect/config seeding cannot target a different image.
ACTIVE_IMAGE="$(minipc_env_value "${INSTALL_DIR}/.env" NEURON_IMAGE)"
ACTIVE_STUB_IMAGE="$(minipc_env_value "${INSTALL_DIR}/.env" REMOTE_STUB_IMAGE)"
ACTIVE_NGINX_IMAGE="$(minipc_env_value "${INSTALL_DIR}/.env" NGINX_IMAGE)"
NEURON_IMAGE="${ACTIVE_IMAGE:-${NEURON_IMAGE}}"
REMOTE_STUB_IMAGE="${ACTIVE_STUB_IMAGE:-${REMOTE_STUB_IMAGE}}"
NGINX_IMAGE="${ACTIVE_NGINX_IMAGE:-${NGINX_IMAGE}}"
if [[ -z "${BUNDLE_DIR}" && -n "${ENV_EXAMPLE_SRC}" ]]; then
  rm -f "${ENV_EXAMPLE_SRC}"
fi

if [[ "${EUID}" -ne 0 ]] && [[ -n "${USER:-}" ]]; then
  ${SUDO} chown -R "${USER}:$(id -gn)" "${INSTALL_DIR}"
fi

if [[ -n "${STACK_IMAGE_TAR:-}" ]]; then
  echo ">> docker load stack (Neuron + remote-stub + proxy) from ${STACK_IMAGE_TAR}"
  DKR load -i "${STACK_IMAGE_TAR}"
fi
if [[ -n "${IMAGE_TAR:-}" ]]; then
  echo ">> docker load Neuron image from ${IMAGE_TAR}"
  DKR load -i "${IMAGE_TAR}"
fi
if [[ -n "${STUB_IMAGE_TAR:-}" ]]; then
  echo ">> docker load stub image from ${STUB_IMAGE_TAR}"
  DKR load -i "${STUB_IMAGE_TAR}"
fi

if [[ "${SKIP_DOCKER_PULL}" == "1" ]]; then
  echo ">> Bỏ qua docker pull (SKIP_DOCKER_PULL=1 hoặc đã dùng STACK_IMAGE_TAR)."
else
  echo ">> docker pull images"
  DKR pull "${NEURON_IMAGE}"
  DKR pull "${REMOTE_STUB_IMAGE}"
  DKR pull "${NGINX_IMAGE}"
fi

minipc_require_image "${NEURON_IMAGE}"
minipc_require_image "${REMOTE_STUB_IMAGE}"
minipc_require_image "${NGINX_IMAGE}"

minipc_disable_native_neuron

minipc_seed_config_from_image

echo ">> docker compose up -d"
( cd "${INSTALL_DIR}" && DC up -d )

if [[ "${NEURON_CONFIG_CHANGED}" == "1" ]] && DKR inspect neuron-minipc >/dev/null 2>&1; then
  echo ">> Restart Neuron để nạp các file cấu hình mới"
  ( cd "${INSTALL_DIR}" && DC restart neuron ) || true
fi

minipc_wait_healthy neuron-minipc "Neuron"
minipc_wait_healthy neuron-remote-stub "Remote backend"
minipc_wait_healthy neuron-edge-proxy "Edge proxy"

HTTP_PORT_LINE="$(grep -E '^NEURON_HTTP_PORT=' "${INSTALL_DIR}/.env" 2>/dev/null | tail -1 || true)"
STUB_PORT_LINE="$(grep -E '^REMOTE_STUB_HTTP_PORT=' "${INSTALL_DIR}/.env" 2>/dev/null | tail -1 || true)"
STUB_BIND_LINE="$(grep -E '^REMOTE_STUB_BIND=' "${INSTALL_DIR}/.env" 2>/dev/null | tail -1 || true)"
HTTP_PORT="${NEURON_HTTP_PORT:-80}"
STUB_PORT="${REMOTE_STUB_HTTP_PORT:-18080}"
STUB_BIND="${REMOTE_STUB_BIND:-127.0.0.1}"
if [[ -n "${HTTP_PORT_LINE}" ]]; then
  HTTP_PORT="${HTTP_PORT_LINE#NEURON_HTTP_PORT=}"
fi
if [[ -n "${STUB_PORT_LINE}" ]]; then
  STUB_PORT="${STUB_PORT_LINE#REMOTE_STUB_HTTP_PORT=}"
fi
if [[ -n "${STUB_BIND_LINE}" ]]; then
  STUB_BIND="${STUB_BIND_LINE#REMOTE_STUB_BIND=}"
fi
if [[ "${HTTP_PORT}" == "80" ]]; then
  echo ">> Neuron UI (qua proxy): http://127.0.0.1/"
else
  echo ">> Neuron UI (qua proxy): http://127.0.0.1:${HTTP_PORT}/"
fi
echo ">> Remote stub diagnostic: http://${STUB_BIND}:${STUB_PORT}/docs"
echo ">> Remote API qua cùng địa chỉ UI: /api/v2/remote/connection"
echo "Done. Ba dịch vụ đã healthy."
