---
name: dgx-gpu-diagnostics
description: Use when diagnosing CUDA, NVIDIA GPU, or GPU allocation problems on DGX worker nodes.
---

# DGX GPU Diagnostics

**REQUIRED BACKGROUND:** Resolve DGX reference facts from the user's
**personal notes** collection via the `personal-notes` skill. Navigate from the
collection's `index.md` searching for information about DGX usage (topic "DGX
system (reference)"). **Never hardcode a note path** — notes may be renamed or
reorganized; the index is the stable entry point. Load **only the sections this
workflow needs** (below), never the whole collection, to protect the context
window.

Sections of the DGX topic note used by this workflow:

- **Architecture & access** — SSH/`ekca-client-osum` transport, node model,
  non-interactive usage.
- **Discovery** — the `dgx_discovery.sh` helper and the required output tables.
- **Slurm, containers, profiles** — Slurm/module setup, tmux ownership, the
  container image and the `gpu-python-vllm-test` profile.
- Pull further sections (e.g. Storage, Registries) only if a task actually
  requires them; do not load them preemptively.

This skill owns only orchestration: access, discovery, user choices, Slurm
allocation, tmux ownership, container startup, invocation of
`<skilldir>/gpu_diagnostics.py`, result presentation, and cleanup.

## Workflow

1. Resolve access per the DGX topic note's **Architecture & access** section:
   try local `dgx`, ask the user to run `ekca-client-osum` interactively when
   authentication is missing, then retry. If no `dgx` alias exists, ask which
   documented transport to use.
2. Copy the discovery helper from the personal-notes asset referenced by the
   DGX topic note (under `assets/dgx/`) into a unique head-node-local
   `/tmp/dgx-gpu-diagnostics-XXXXXX/` directory and execute it there.
3. Render all three required discovery tables exactly as specified by the DGX
   topic note's **Discovery** section: Worker Node Liveness, Active GPU-Related
   Jobs, and Active CPU-Only Jobs. Never silently skip an occupied node.
4. Ask which discovered nodes to test. Test sequentially. If the user selected
   all nodes, continue sequentially without an intermediate confirmation;
   otherwise ask after each completed node whether to test another.
5. For each selected node, request its full configured GPU count. A full
   allocation proceeds. A partial or pending allocation requires offering:
   wait, choose another node, or continue with the available GPUs. An
   allocation failure is reported and another node may be selected.
6. Ask which container image to use, recommending the vLLM image and offering
   the optional `gpu-python-vllm-test` profile as documented in the DGX topic
   note's **Slurm, containers, profiles** section, without imposing that
   profile on other DGX workflows.
7. Reuse an existing head-node tmux session when possible and create a
   uniquely named owned window using a session-qualified tmux target. If none
   exists, create a temporary session. In the window, initialize the module
   system, load the Slurm version documented in the DGX topic note, verify
   `command -v srun`, and explicitly add the configured Slurm bin and library
   paths if the command is still absent. Start the container with the selected
   profile, `bash -l` by default, and validate `python3`, PyTorch, CUDA
   initialization, and GPU visibility before running tests.
8. Run `<skilldir>/gpu_diagnostics.py` once per assigned UUID, sequentially,
   with `CUDA_VISIBLE_DEVICES` set to that UUID. Continue after recognized
   JSON `FAIL` results. Use an allocation time long enough for image import
   and the fixed workload; `--time=30` is only the discovery probe timeout,
   not a safe GPU-test allocation timeout.
9. A non-zero exit without valid JSON, missing dependencies, malformed output,
   or incompatible CUDA/PyTorch environment is a diagnostic execution error,
   not a GPU failure. Stop the node test immediately and ask whether to keep
   the allocation/tmux window for debugging or clean them up.
10. Merge each script result with `nvidia-smi` metadata and show a summary
    followed by the detailed table. Always include GPU index, UUID, model,
    driver, memory, and result.
11. After normal completion, recognized GPU failures, or successful cleanup,
    automatically release the owned Slurm allocation and close only the owned
    tmux window. Preserve pre-existing tmux sessions and windows. On execution
    errors, follow the user’s keep/cleanup choice.

## Progress Polling

Poll the owned tmux window and Slurm job at intervals of no more than 30
seconds while waiting for image import, container readiness, or sequential GPU
results. Report intermediate progress instead of blocking for a single long
sleep. Do not treat 30 seconds as a per-GPU test deadline: the fixed
memory-and-CUDA workload may legitimately take longer.

Before polling, confirm the job exists and is assigned to the requested node.
If the window shows `srun: command not found`, stop and repair the Slurm
environment rather than classifying the result as a GPU failure.

## Stable Result Format

For every tested node, render one separate table. Always place the node
summary immediately before its table:

```text
Node: <node>
Result: <passed>/<tested> GPUs passed
```

| GPU | UUID | Model | Driver | Memory | Result |
|---:|---|---|---|---:|---|
| `<index>` | `<uuid>` | `<model>` | `<driver>` | `<memory>` | `PASS` or `FAIL` |

After all selected nodes are complete, report the overall total, for example:
`Overall: 16/16 GPUs passed.`

## Required Per-Node Output

```text
Node: <node>
Result: <passed>/<tested> GPUs passed
```

| GPU | UUID | Model | Driver | Memory | Result |
|---:|---|---|---|---:|---|
| `<index>` | `<uuid>` | `<model>` | `<driver>` | `<memory>` | `PASS` or `FAIL` |
