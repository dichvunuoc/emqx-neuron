#!/usr/bin/env bash
set -euo pipefail

DATA_DIR=/data
DEFAULT_CONFIG_DIR="/opt/neuron-defaults/config"

install -d -m 0750 \
  "${DATA_DIR}" \
  "${DATA_DIR}/config" \
  "${DATA_DIR}/logs" \
  "${DATA_DIR}/persistence" \
  "${DATA_DIR}/remote-stub" \
  /tmp/nginx-client-body \
  /tmp/nginx-proxy \
  /tmp/nginx-fastcgi \
  /tmp/nginx-uwsgi \
  /tmp/nginx-scgi

# Seed new defaults and migrations without overwriting runtime configuration.
while IFS= read -r -d '' source_file; do
  relative_path="${source_file#"${DEFAULT_CONFIG_DIR}"/}"
  destination="${DATA_DIR}/config/${relative_path}"
  if [[ ! -f "${destination}" ]]; then
    install -d -m 0750 "$(dirname "${destination}")"
    install -m 0644 "${source_file}" "${destination}"
  fi
done < <(find "${DEFAULT_CONFIG_DIR}" -type f -print0)

# A named volume can come from an older image or be created separately. Repair
# ownership before dropping privileges so upgrades keep working on every host.
chown -R neuron:neuron "${DATA_DIR}"
chown -R neuron:neuron \
  /tmp/nginx-client-body \
  /tmp/nginx-proxy \
  /tmp/nginx-fastcgi \
  /tmp/nginx-uwsgi \
  /tmp/nginx-scgi

if [[ $# -eq 0 ]]; then
  set -- /usr/bin/supervisord -c /etc/neuron-remote/supervisord.conf
fi

# Supervisor stays as PID 1's child so it can attach all program logs to the
# root-owned Docker stdout/stderr pipes. Each managed service drops to neuron.
if [[ "$1" == "/usr/bin/supervisord" ]]; then
  exec "$@"
fi

exec gosu neuron:neuron "$@"
