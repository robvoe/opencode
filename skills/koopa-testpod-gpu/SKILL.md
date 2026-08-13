---
name: koopa-testpod-gpu
description: Use when the user wants to spin up a temporary, interactive GPU test pod in the koopa kubernetes environment (LLM namespaces like mf-llm-qa), so they can poke around and test things on a real GPU (T4 / A100 / H100) with a real network-mounted model store. Runs a GPU-centric two-survey flow: (1) ask only the environment (QA/intg or live/prod, never the datacenter/cluster), run the scout script and present its plain output as a markdown grid table (columns = GPU classes), then (2) foreground the GPU-class decision and settle all pod specs — GPU class/VRAM, CPU, RAM, image, volume mount, security context — before deploying the manifest, verifying GPU + mount from inside, and exec-ing into the shell. Use ONLY when targeting these koopa clusters.
---

# koopa-testpod-gpu

Spin up a **temporary GPU test pod** in the koopa Kubernetes clusters (the LLM namespaces: `mf-llm-*`, `mf-sda-llm-*`). It is an interactive, disposable environment: a real GPU, a network-mounted model store, and a shell to poke around in. Nothing about it is persistent.

Two environments exist, picked per run:
- **QA (intg)** — default. Contexts contain `intg`. `be-intg-iz1-bs` has the whole GPU ladder (T4, A100 full + A100 MIG, H100 MIG); `be-intg-iz2-bap` has T4 only.
- **live (prod)** — explicit opt-in. Contexts contain `prod` (`be-prod-iz1-bs`, `be-prod-iz2-bap`).

## Cluster naming schema — and why the user never picks a cluster

Company cluster names always follow `{stack}-{env}-{zone}-{site}`:

| part | meaning | values |
|---|---|---|
| stack | role | `be` (backend), `fe` (frontend), `infra` |
| env | environment | `intg` (QA) or `prod` (live) |
| zone | datacenter zone | `iz1`, `iz2` |
| site | site/shard | `bs`, `bap`, `lxa` |

e.g. `be-intg-iz1-bs`, `be-prod-iz2-bap`. The GPU-capable clusters are all `be-*`.
**The user never decides upon the datacenter or the cluster.** The scout derives every `be-{env}-*` context automatically from the environment choice (QA/intg or live/prod) — the board simply reports which clusters carry which GPU units.

## GPU units — the landscape (columns are the GPU classes; everything is GPU-centric)

| | T4 | A100 full | A100 MIG | H100 MIG |
|---|---|---|---|---|
| Node label | `nvidia.com/gpu.tesla-t4` | `nvidia.com/gpu.ampere-a100` | `nvidia.com/gpu.ampere-a100` | `nvidia.com/gpu.hopper-h100` |
| Resource to request | `nvidia.com/gpu` | `nvidia.com/gpu` | `nvidia.com/mig-7g.40gb` | `nvidia.com/mig-7g.94gb` |
| VRAM per allocation | 15 GiB | ~80 GiB | 40 GiB | 94 GiB |
| Allocations/node | 1–2 | 1 | 1 | 2 |
| Machine envelope | 64–104c / 374 Gi, or 256c / 753 Gi | 256c / 753 Gi | 256c / 753 Gi | 128c / 374 Gi |
| Reservation taint | none (open pool) | yes | yes | yes |
| Clusters | iz1 + iz2 | iz1 | iz1 | iz1 |

## Presenting the board — one-shot reference

After Survey 1, render the board as a markdown grid **exactly in this shape**: `|`-separated columns with a `|---|---|` separator row, columns = GPU classes, rows = attributes, live values (Beds in use, Cluster(s)) from the scout output — all other rows from the GPU units table above:

| Attribute | T4 | A100 full | A100 MIG | H100 MIG |
|---|---|---|---|---|
| Node label | `nvidia.com/gpu.tesla-t4` | `nvidia.com/gpu.ampere-a100` | `nvidia.com/gpu.ampere-a100` | `nvidia.com/gpu.hopper-h100` |
| Resource to request | `nvidia.com/gpu` | `nvidia.com/gpu` | `nvidia.com/mig-7g.40gb` | `nvidia.com/mig-7g.94gb` |
| VRAM per allocation | 15 GiB | ~80 GiB | 40 GiB | 94 GiB |
| Allocations/node | 1–2 | 1 | 1 | 2 |
| Machine envelope | 64–104c / 374 Gi, or 256c / 753 Gi | 256c / 753 Gi | 256c / 753 Gi | 128c / 374 Gi |
| Reservation taint | none (open pool) | yes | yes | yes |
| **Beds in use** | **9/14** | **2/2** | **0/1** | **2/2** |
| Cluster(s) | iz1 + iz2 | iz1 | iz1 | iz1 |

Columns are GPU-class-centric because everything in a test pod runs on a specific GPU class.

For A100/H100, add the reservation-taint toleration:
```yaml
tolerations:
  - key: resources.po.k8s.zone/gpu_reservation
    operator: Exists
    effect: PreferNoSchedule
```

Deciding the GPU class means deciding four GPU-centric axes:
1. **Allocation mode** — full card (`nvidia.com/gpu`) vs MIG slice (`nvidia.com/mig-7g.*`). Changes the resource *name*.
2. **VRAM** — 15 / 40 / 94 GiB. The decisive constraint for model size.
3. **Bundled CPU/RAM** — the node envelope riding along (fat 256c/753Gi boxes run big preprocessing alongside).
4. **Reservation zone** — A100/H100 = reserved pool (tainted); T4 = open pool (untainted).

## Images (harbor registry)

Known-good images:
- `dpo-harbor.infra.server.lan/dgx-mirror/nvidia/tritonserver:25.03-py3-sdk`
- `dpo-harbor.infra.server.lan/dgx-mirror/vllm/vllm-openai:v0.24.0`
- `dpo-harbor.infra.server.lan/dgx-registry/mf/dgx-python:0.9.1`

Or any image the user supplies.

## Security context — the UID is an optional Survey 2 choice

Settle the security context every time; `runAsUser` defaults to **47090 for all namespaces**, with the image-default user as the alternative:

| Option | What it sets | Consequences |
|---|---|---|
| **1. `47090` (default, all namespaces)** | `runAsUser: 47090`, `runAsNonRoot: true`; `fsGroup: 21655691` in live namespaces only | UID not in image → `HOME=/`, "I have no name!" — cosmetic; writable caches via the `emptyDir` mounted at `/tmp` + `/home/vllm`. A workload that needs `$HOME` exports its own |
| **2. image default user (UID ~1000)** | drop `runAsUser` (or `runAsUser: 1000`) | UID present in the image → real home, shell prompt, pip/HF caches all work |

The pod runs `sleep infinity`, so these are ergonomics (prompt, caches, writable home), not functionality. In Survey 2, default to `47090` but explicitly offer option 2 rather than assuming. The container root FS is **read-only for both options regardless of UID** — the `emptyDir` scratch mount is what makes `/tmp` writable, so always keep it in the manifest.

## Procedure (two surveys, then deploy)

**Survey 1 — the environment (only what the scout needs).**
Ask exactly one thing: which environment — **QA (intg, default)** or **live (prod, explicit opt-in)** — and settle the target namespace. Never ask about datacenter or cluster; those are derived automatically. Then immediately run the read-only scout:

```bash
bash <skill-base>/scripts/scout.sh intg        # or: prod, optionally a namespace filter
```

Present the produced **GPU-centric board** to the user. The scout outputs plain aligned text — **you (the agent) reformat it into the markdown grid table** shown in the *Presenting the board* one-shot above (columns = GPU classes), filling in the static attribute rows from the *GPU units* table above and the live `Beds in use` / `Cluster(s)` values from the scout output. Also relay the per-node detail and the per-namespace lines: the **model store** (RWX NFS PVC, e.g. `mf-llm-qa-nonlive-nfs-llm-model`) and the **GPU quota headroom** (`requests.nvidia.com/gpu=used/hard`). A namespace with `used/hard == hard` is **quota-blocked** even if nodes are free; a namespace with `store: NO MODEL-STORE PVC` cannot mount the model store — switch namespaces (or let the scheduler work across the derived clusters) and re-run the scout.

**Survey 2 — the pod specs, GPU in the foreground.**
The GPU class is the primary decision — lead with it, pointing at the board above:

1. **GPU class + VRAM** — the decisive choice (T4 / A100 full / A100 MIG / H100 MIG). Scout's `Beds in use` tells you what's realistically obtainable; the resource key + nodeSelector follow from the class (remember MIG vs full).
2. CPU count and RAM amount (ask every time)
3. Image (the known three, or user-supplied)
4. Volume / PVC: the existing namespace model-store PVC (e.g. `mf-llm-qa-nonlive-nfs-llm-model`) or a user-chosen claim
5. Mount path: default `/mnt/network-mount/`
6. Security context (see table above): **`runAsUser` → default `47090` for all namespaces**, or option 2 = the image's default user (UID ~1000); then settle `runAsNonRoot` and `fsGroup` (live only)
7. Pod name: base (default `test-pod-gpu`) **with the username appended**, e.g. `test-pod-gpu-rvoelckner` (`$USER`/`whoami`). Also add an `owner: <username>` label so the pod is attributable and cleanable.

**Then deploy:**
1. **Render the manifest.** Start from the template below, substitute the settled values. Note `nodeSelector` lives at `spec` level (not inside the container).
2. **Apply & wait.** `kubectl --context=<ctx> -n <ns> apply -f <manifest>` then poll for Running. Image pulls of the big images (vLLM especially) take minutes — do not give up after a short timeout.
3. **Verify from inside.** `kubectl ... exec` and confirm with `nvidia-smi` (expect the negotiated GPU, e.g. `Tesla T4`), that the emptyDir mounts are writable (`touch /tmp/.t && touch /home/vllm/.t`), that the NFS store is mounted at the chosen path with the models visible, and that the model-store mount is genuinely read-only (`touch /mnt/network-mount/.write-test` must fail).
4. **Hand over.** Give the user the interactive exec command; remind that exec not ssh, and the cleanup delete command.

## Manifest template

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: test-pod-gpu-rvoelckner   # <base>-<username>; settle base with user, append $USER
  namespace: mf-llm-qa        # settle with user
  labels:
    app: test-pod-gpu
    owner: rvoelckner         # username, for attribution/cleanup
spec:
  securityContext:            # default 47090 (all ns); option 2 = image default user, drop runAsUser
    runAsUser: 47090
    runAsNonRoot: true
    # fsGroup: 21655691       # only for live namespaces
  # tolerations:              # only when targeting A100/H100 (reservation taint)
  #   - key: resources.po.k8s.zone/gpu_reservation
  #     operator: Exists
  #     effect: PreferNoSchedule
  volumes:
    - name: model-store
      persistentVolumeClaim:
        claimName: mf-llm-qa-nonlive-nfs-llm-model   # settle with user
    - name: scratch
      emptyDir:
        sizeLimit: 50Gi       # node-local, wiped with the pod
  containers:
    - name: test-pod-gpu
      image: dpo-harbor.infra.server.lan/dgx-mirror/vllm/vllm-openai:v0.24.0  # settle
      command: ["sleep"]
      args: ["infinity"]
      volumeMounts:
        - mountPath: /mnt/network-mount/       # default, settle with user
          name: model-store
          readOnly: true
        - mountPath: /tmp                      # container root FS is read-only; emptyDir makes /tmp writable
          name: scratch
        - mountPath: /home/vllm                # writable HOME for vLLM-style workloads
          name: scratch
      resources:
        requests:
          nvidia.com/gpu: 1                    # MIG tiers use nvidia.com/mig-7g.*gb instead
          memory: 8Gi
          cpu: 1
        limits:
          nvidia.com/gpu: 1
          memory: 16Gi
          cpu: 2
  nodeSelector:
    nvidia.com/gpu.tesla-t4: "1"               # see table below - set to the chosen tier
```

The `nodeSelector` must match the settled tier:
- T4 → `nvidia.com/gpu.tesla-t4: "1"`
- A100 → `nvidia.com/gpu.ampere-a100: "1"`
- H100 → `nvidia.com/gpu.hopper-h100: "1"`

## Serving with vLLM — distilled hints

When the user wants to spin up a vLLM server on the pod (e.g. `gemma-3-4b-it`):

- **Launch with `python3`, not `python`** — the vllm image has no `python` binary. Use `python3 -m vllm.entrypoints.openai.api_server`. (The image also ships `python3`-based `/usr/local/bin/vllm`; `/usr/local/bin/vllm-nonroot-entrypoint.sh` sets HOME, USER, and an /etc/passwd entry for UID 47090 — but that **only applies when the image runs that entrypoint**. Launching via bare `python3` bypasses it, so the container has *no* passwd entry for UID 47090; see the `USER`/`LOGNAME` bullet below.)
- **Point HOME at the emptyDir** — the image runs UID 47090 (HOME=`/`, unwritable). `export HOME=/home/vllm` so HF/vLLM/Triton caches land in the writable emptyDir, not `/.cache` or the NFS store.
- **`export USER` and `LOGNAME` or torch dies at import** — with no `/etc/passwd` entry for UID 47090, `torch._dynamo` builds its cache dir via `getpass.getuser()`, which falls back to `pwd.getpwuid(47090)` and crashes with `KeyError: 'getpwuid(): uid not found: 47090'`. This happens on *every* vLLM/torch import (not just servers), before the server even starts. Fix: set `USER` and `LOGNAME` in the launch environment (getpass returns the env var and never touches `pwd`), and pin caches to the writable emptyDir: `export USER=vllm LOGNAME=vllm TORCHINDUCTOR_CACHE_DIR=/home/vllm/torch_inductor_cache XDG_CACHE_HOME=/home/vllm/.cache`. These must be in the same `sh -c` that launches the server — setsid-exports don't carry across exec invocations.
- **The container root FS is read-only** — `/tmp`, `/var/tmp`, `/home/vllm` are unwritable despite perms ("Read-only file system"). This kills `tempfile`/torch import (`No usable temporary directory found`). The `emptyDir` mounts in the template are what make `/tmp` and `/home/vllm` writable; nothing should point at NFS.
- **For local serving, set `HF_HUB_OFFLINE=1`** so vLLM never tries the network.
- **Models in the store are HF-hub-cache layout**: `…/.cache/huggingface/hub/models--google--gemma-3-4b-it/snapshots/<hash>/`. Point `--model` at the snapshot dir directly; add `--served-model-name <short>` for a clean API name.
- **Launch detached** (exec sessions get killed when they return): `setsid nohup python3 -m vllm.entrypoints.openai.api_server --model <snapshot> --host 0.0.0.0 --port 8000 --gpu-memory-utilization 0.9 --max-model-len <n> > /home/vllm/vllm.log 2>&1 < /dev/null &`, then poll `curl -s localhost:8000/health` until `200`. First start compiles CUDA graphs — minutes are normal, don't give up.
- **Peek at the log right after launching, and stream it — don't poll `/health` in the dark and don't wait for the last N lines.** A detached server can die at import within seconds (e.g. the `getpwuid` KeyError above), and a minutes-long health poll would only reveal that belatedly. Tail the log a few seconds after launch and show the user what's there immediately — `tail -f vllm.log` streams, so the moment a line lands (error or "Starting vLLM server …") it's visible instead of being held until a chunk of N lines accumulates. Early failures show up in seconds, not minutes.
- **Don't `pkill -f <pattern>` from an exec'd `sh -c`** — the pattern string is in your own command line, so it self-matches and SIGTERMs your exec (exit code 143). Kill by PID instead.
- **Reach the server from your laptop** with `kubectl --context=<ctx> -n <ns> port-forward pod/<pod> 8000:8000`.

## Access & cleanup

```bash
kubectl --context=<ctx> -n <ns> exec -it <pod> -- /bin/bash   # or /bin/sh
kubectl --context=<ctx> -n <ns> cp <ns>/<pod>:<path> ./local  # files out
kubectl --context=<ctx> -n <ns> delete pod <pod>              # cleanup when done
```

## Pitfalls / warnings

- **Namespace quota gates the deploy** even when nodes are free — always check `requests.nvidia.com/gpu=used/hard` in scout output before applying. `iz1/mf-llm-qa` was 4/4 (blocked); `iz2/mf-llm-qa` had 3 slots free. Fall back across clusters/namespaces.
- **The model store is namespace-pinned** — the NFS model store is a *static* PV (`storageClassName: None`, `Retain`) bound by `claimRef` to one specific namespace (e.g. `mf-llm-qa-nonlive-nfs-llm-model` in `mf-llm-qa`). It can **only** be mounted from that namespace — never from another (e.g. `mf-sda-llm-qa` shows `NO MODEL-STORE PVC`). Pick the namespace, or accept no model store; the scout's `store:` column makes this visible in Survey 1.
- **MIG vs full changes the resource name** (`nvidia.com/gpu` vs `nvidia.com/mig-7g.40gb` / `mig-7g.94gb`). Requesting the wrong one fails to schedule.
- **`nodeSelector` lives at `spec` level** — nesting it inside the container yields a strict-decoding error ("unknown field spec.containers[0].nodeSelector").
- **A100/H100 nodes are tainted** — without the toleration a T4-style manifest will not land on them.
- Prefer a **manifest file over `kubectl run --overrides`**: the giant JSON override is error-prone and hard to audit.
- **vLLM/triton images are GBs** — pulling takes several minutes; `ContainerCreating` for 3–5 min is normal.
- The default `kubectl` context is a **prod cluster** — always pass `--context` explicitly.
- **Container root FS is read-only** — `/tmp`, `/var/tmp`, `/home/vllm` are *not writable* despite perms (`touch` → "Read-only file system"). This breaks `tempfile`/torch/pip (`No usable temporary directory found`). Fix: the `emptyDir` skeleton mounted at `/tmp` and `/home/vllm` in the template — never work around it by writing to the NFS store.
- **Never write to the model store** — the NFS PVC is shared multi-tenant infrastructure and is mounted **read-only** in the template; any legitimate scratch/cache/HOME goes to the `emptyDir`. Writing results back to the store requires an explicit user request to remount rw.
- UID without an `/etc/passwd` entry (e.g. 47090) → "I have no name!" **and `HOME=/` (unwritable)** — cosmetic for shell poking, but breaks pip/HF caches and anything needing a temp dir; the `emptyDir` mounted at `/tmp` covers temp, `/home/vllm` covers HOME (vllm image's nonroot entrypoint auto-points there). Don't "fix" it by scratching onto the NFS store. Note: the missing passwd entry is **fatal, not just cosmetic, for torch workloads** — `torch._dynamo` import fails with `KeyError: 'getpwuid(): uid not found: 47090'` unless `USER`/`LOGNAME` are exported (getpass takes the env var and skips `pwd`).
