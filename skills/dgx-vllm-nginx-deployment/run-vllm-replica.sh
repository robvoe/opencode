#!/usr/bin/env bash
set -euo pipefail

: "${PORT:?Set PORT to a unique confirmed model port}"
: "${MODEL_IMAGE:?Set MODEL_IMAGE to an explicit versioned pyxis image}"
: "${WORKER:?Set WORKER to the confirmed Slurm worker}"
: "${SERVE_SCRIPT:?Set SERVE_SCRIPT to the staged in-container serving script}"

command -v module >/dev/null 2>&1 && module load slurm
command -v srun >/dev/null 2>&1 || PATH="/cm/shared/apps/slurm/current/bin:/cm/shared/apps/slurm/current/sbin:$PATH"

export PORT
export NVIDIA_VISIBLE_DEVICES=all
export NVIDIA_DRIVER_CAPABILITIES=compute,utility

exec srun --pty --interactive \
  --job-name="${DEPLOYMENT_ID:-vllm}-${PORT}" \
  --container-image="$MODEL_IMAGE" \
  --nodelist="$WORKER" \
  --container-env=NVIDIA_VISIBLE_DEVICES,NVIDIA_DRIVER_CAPABILITIES,PORT \
  --gres=gpu:1 \
  --cpus-per-task="${CPUS_PER_REPLICA:-8}" \
  --container-mounts=/export:/export,/scratch:/scratch \
  --container-mount-home \
  --container-writable \
  --no-container-entrypoint \
  bash -lc "bash '$SERVE_SCRIPT'"
