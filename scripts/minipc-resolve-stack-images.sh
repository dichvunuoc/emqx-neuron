#!/usr/bin/env bash
# Gán NEURON_IMAGE + REMOTE_STUB_IMAGE từ một registry + tag chung (khi chưa set riêng).
# Source từ repo:  source "$(dirname "$0")/minipc-resolve-stack-images.sh" && minipc_resolve_stack_images
#
# Env:
#   STACK_REGISTRY   ví dụ: registry.example.com/iot  → .../neuron-full:TAG và .../neuron-remote-stub:TAG
#   STACK_TAG        mặc định: latest
# Hoặc set sẵn NEURON_IMAGE / REMOTE_STUB_IMAGE (hoặc STUB_IMAGE alias cho stub) — không ghi đè.
#
minipc_resolve_stack_images() {
  local tag="${STACK_TAG:-latest}"
  if [[ -n "${STACK_REGISTRY:-}" ]]; then
    NEURON_IMAGE="${NEURON_IMAGE:-${STACK_REGISTRY}/neuron-full:${tag}}"
    REMOTE_STUB_IMAGE="${REMOTE_STUB_IMAGE:-${STUB_IMAGE:-${STACK_REGISTRY}/neuron-remote-stub:${tag}}}"
  else
    NEURON_IMAGE="${NEURON_IMAGE:-neuron-full:local}"
    REMOTE_STUB_IMAGE="${REMOTE_STUB_IMAGE:-${STUB_IMAGE:-neuron-remote-stub:local}}"
  fi
}
