#!/usr/bin/env bash
set -euo pipefail

: "${LB_IMAGE:?Set LB_IMAGE explicitly}"
: "${WORKER:?Set WORKER to the confirmed Slurm worker}"
: "${CONFIG_DIR:?Set CONFIG_DIR to the staged worker config directory}"
: "${CERT_DIR:?Set CERT_DIR to the user-supplied certificate directory}"
: "${LB_PORT:?Set LB_PORT}"

command -v module >/dev/null 2>&1 && module load slurm
command -v srun >/dev/null 2>&1 || PATH="/cm/shared/apps/slurm/current/bin:/cm/shared/apps/slurm/current/sbin:$PATH"

exec srun --pty --interactive \
  --job-name="${DEPLOYMENT_ID:-vllm}-nginx" \
  --container-image="$LB_IMAGE" \
  --nodelist="$WORKER" \
  --gres=gpu:0 \
  --cpus-per-task="${NGINX_CPUS:-2}" \
  --container-mounts="$CONFIG_DIR:/config:ro,$CERT_DIR:/keys:ro" \
  --container-mount-home \
  --container-writable \
  --no-container-entrypoint \
  /usr/sbin/nginx -c /config/nginx.conf -g 'daemon off;'
