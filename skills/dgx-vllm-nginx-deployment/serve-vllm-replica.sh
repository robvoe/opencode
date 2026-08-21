#!/usr/bin/env bash
set -euo pipefail

: "${PORT:?Set PORT}"
: "${VLLM_SERVE_COMMAND:?Set the verified vLLM command template}"

export HF_HUB_OFFLINE="${HF_HUB_OFFLINE:-1}"
export PORT

# VLLM_SERVE_COMMAND is rendered only after inspection and the first-replica gate.
# It must use "$PORT" for the per-replica port and must not include TLS flags when
# nginx owns TLS.
eval "exec ${VLLM_SERVE_COMMAND}"
