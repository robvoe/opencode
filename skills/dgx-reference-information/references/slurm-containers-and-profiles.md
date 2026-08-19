# Slurm, Containers, And Profiles

## Stable Rules

- GPUs are available on worker nodes through Slurm, not by assuming direct bare-metal access.
- Pyxis/enroot starts container images from `srun`.
- Enroot does not run Docker entrypoints automatically; specify the intended command.
- The home directory is normally mounted automatically. Treat it as code/config space, not bulk-data storage.
- Ports are exposed directly on the worker host and must be unique.
- Use tmux for long-running interactive or non-interactive workflows.
- `module load slurm/slurm/<version>` may be needed before `srun`, `squeue`, `sinfo`, or `scontrol`.
- tmux commands do not necessarily inherit the interactive module environment. In the owned window, initialize the module system, load Slurm, then verify `command -v srun`; if it is still absent, explicitly prepend `/cm/shared/apps/slurm/current/bin` and `/cm/shared/apps/slurm/current/sbin` and set the matching library paths before starting work.

## Common Options

Use `--gres=gpu:<count>` for GPU count and set `NVIDIA_VISIBLE_DEVICES=all` plus `NVIDIA_DRIVER_CAPABILITIES=compute,utility` when GPU libraries are needed. Common mounts are `/export:/export` and `/scratch:/scratch`; choose mounts for the specific workflow.

## Optional Profile: gpu-python-vllm-test

Downstream GPU-testing workflows may offer this profile, but it is not a universal DGX default:

```text
Image: dpo-harbor.infra.server.lan#/dgx-mirror/vllm/vllm-openai:v0.24.0
Mounts: /export:/export,/scratch:/scratch
Flags: --container-mount-home --container-writable --no-container-entrypoint
GPU env: NVIDIA_VISIBLE_DEVICES=all NVIDIA_DRIVER_CAPABILITIES=compute,utility
Shell: bash -l
```

The login shell may emit a non-fatal `/usr/bin/tclsh` warning. Record it separately; do not call it a GPU failure unless it prevents the prerequisites from running. Use `bash` only if login initialization blocks the test.

## Tmux Ownership

Reuse an existing head-node tmux session when present and create a uniquely named owned window. If no session exists, create a temporary session. Normal completion removes only resources created by the workflow; pre-existing sessions and windows remain intact.

Use a session-qualified target such as `session:window-name` when creating,
sending keys to, or capturing the owned window. A numeric target such as
`-t 0` can refer to an existing window index and fail with `index 0 in use`.
