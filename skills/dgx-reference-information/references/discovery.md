# DGX Discovery

Discovery runs after access to the head node has succeeded. Stage `<skilldir>/dgx_discovery.sh` into a unique head-node-local `/tmp/dgx-reference-information-XXXXXX/` directory and execute it there. The helper emits JSON Lines and continues when one worker probe fails.

## Signals

- Deduplicate worker nodes from Slurm.
- Read Slurm state, configured GPU resources, CPU capacity, allocations, daemon version, and load.
- Check TCP/22 reachability from the head node.
- Run a CPU-only one-task probe: `srun --nodelist=<node> --ntasks=1 --cpus-per-task=1 --gres=gpu:0 --time=30 hostname`, with a local timeout slightly above 30 seconds.
- Inspect active jobs assigned to discovered workers.
- GPU-related means a parsed positive GPU request, including typed forms such as `gres:gpu:h100:8`; `gres:gpu:0` is CPU-only.

## Required Tables

Always render all three tables, even when a job table has no rows. Use `None detected` for an empty table.

### Worker Node Liveness

| Node | Slurm State | Health State | Slurm Daemon | TCP/22 | CPU Load | Allocated CPUs | Allocated GPUs | GPU Resources | Result |
|---|---|---|---|---|---:|---:|---:|---|---|
| `<node>` | `<state>` | `<DOWN/DRAIN/NOT_RESPONDING or clear>` | `<status/version>` | `<Reachable/Unavailable>` | `<load>` | `<allocated> / <total>` | `<allocated> / <total>` | `<count> x <type>` | `<Live/FAIL/TIMEOUT>` |

Health state must explicitly identify `DOWN`, `DRAIN`, and `NOT_RESPONDING` when present. Result precedence is scheduler health, then CPU-only Slurm probe, then TCP/22, then `Live`.

### Active GPU-Related Jobs

| Job ID | User | Job Name | State | Node | GPU Request | CPUs |
|---:|---|---|---|---|---:|---:|
| `<id>` | `<user>` | `<name>` | `<state>` | `<node>` | `<count>` | `<cpus>` |

Include only positive GPU requests.

### Active CPU-Only Jobs

| Job ID | User | Job Name | State | Node | GPU Request | CPUs |
|---:|---|---|---|---|---:|---:|
| `<id>` | `<user>` | `<name>` | `<state>` | `<node>` | `0` | `<cpus>` |

Include active non-GPU jobs assigned to discovered workers. Exclude jobs without a worker-node assignment.
