---
name: koopa-testpod-cpu
description: Use when the user wants a temporary CPU-only test pod in the koopa Kubernetes clusters, e.g. "spin up a test pod (CPU only)" with no GPU mention. Scans all contexts and namespaces by default, shows where the user can create pods, settles the pod specs, deploys, verifies and hands over. Do not use for GPU test pods (see koopa-testpod-gpu).
---

# koopa-testpod-cpu

Spin up a **temporary CPU-only test pod** in the koopa Kubernetes clusters: a disposable, interactive environment — `sleep infinity`, a shell to poke around in, and optionally the network-mounted model store. No GPU anywhere in this flow. Nothing about it is persistent.

This is the CPU sibling of `koopa-testpod-gpu`. The GPU skill runs a GPU/capacity scout and a two-step survey; here both are simpler because we make one core assumption:

## The one assumption: CPU is always available

**Do not scout for CPU capacity or node free-CPU.** Test pods are small (default 1/2c, 8/16Gi); free CPUs are never the binding constraint. The *real* deploy gates are:

1. **Namespace `ResourceQuota`** — even if nodes have free CPU, a namespace at its `requests.cpu` hard limit refuses to schedule. Pick for quota headroom, not node free-CPU.
2. **Model-store namespace pinning** — a static NFS store PVC is bound by `claimRef` to exactly one namespace; it can only be mounted *from that namespace* (see below).

## There is no Survey 1 / no environment question

The user is **not** asked whether to deploy in integration or production up front. Everything is scanned and listed at once:

- `scout-cpu.sh` with **no argument scans every context** (`prod|intg|all`, default `all`).
- The context table shows QA and live namespaces side by side, env column marking them.

## Cluster naming — same schema as the GPU skill

Company cluster names follow `{stack}-{env}-{zone}-{site}`. Examples: `be-intg-iz1-bs`, `be-prod-iz2-bap`, `fe-intg-iz1-bs`.

## The pinned placement: `mf-llm-qa`

**Default namespace: `mf-llm-qa`** (on `be-intg-iz1-bs` or `be-intg-iz2-bap`). It is the only team namespace that carries the shared NFS **model store** (`mf-llm-qa-nonlive-nfs-llm-model`). Fallbacks without a model store: `mf-llm-dev`, `mf-sda-llm-dev`, `mf-sda-llm-qa`.

### The model-store namespace-pinning rule

The NFS model store is a *static* PV (`storageClassName: None`, `Retain`) bound by `claimRef` to one namespace. Consequences:

- It can **only** be mounted from `mf-llm-qa` — never from another namespace.
- Frontend clusters (`fe-*`) therefore never have the LLM model store reachable.
- If the user needs the model store, the namespace is effectively **decided**: `mf-llm-qa`.

## Procedure

No Survey 1. The flow is: resolve identity → scout + permissions (one pass) → Survey 2 → render → apply → verify → hand over.

**1. Resolve the identity.** Decode the OIDC token from the kubeconfig exec plugin to get `preferred_username` (e.g. `rvoelckner`). The pod name and `owner` label come from this.

**2. Scout + permissions in one pass.**
```bash
bash <skilldir>/scripts/scout-cpu.sh          # all contexts (or: prod | intg [ns-substring])
bash <skilldir>/scripts/can-create-pods.sh    # RBAC: identity -> # namespaces where pods can be created
```
Present the **context table** (one row per context: env + count of namespaces where the user can create pods) and the **team-relevant namespaces** list, sorted model-store first (see "The pinned placement" above). The user can ask for **all namespaces within a given context** instead — run `scout-cpu.sh <context-basis> ""` or have `can-create-pods.sh` printed for that context.

**3. Survey 2** (the GPU survey minus GPU — no GPU class/VRAM/nodeSelector/taints):
1. Namespace — default `mf-llm-qa`, with the option to list/scan all namespaces in a context; model store only exists in `mf-llm-qa`.
2. CPU count + RAM (default requests 8Gi/1c, limits 16Gi/2c).
3. Image — default `cr.mam.dev/internal/mamido/debian-slim:bookworm` with `command: ["sleep"] args: ["infinity"]`; the user may supply their own image (purpose rides along with the image).
4. PVC — the pinned model store `mf-llm-qa-nonlive-nfs-llm-model` (default) or none. Mount is **read-only by default**; switch to read-write **only** when the user explicitly asks to keep outputs ("can I keep outputs here?").
5. Pod name — base `test-pod-cpu` with the username appended: `test-pod-cpu-rvoelckner`; add an `owner: <username>` label.
6. Security context — `runAsUser` **47090** default (all namespaces), `runAsNonRoot: true`; `fsGroup: 21655691` in live namespaces only. Option 2 = the image's default user (UID ~1000, real home).

**4. Render the manifest.** From the template below. There is **no** GPU resource, **no** nodeSelector, **no** toleration. Network egress is out of scope.

**5. Apply & wait.**
```bash
kubectl --context=<ctx> -n <ns> apply -f <manifest>
```
Poll until the pod is `Running`. `--context` is always passed explicitly — the default kubectl context is a prod cluster.

**6. Verify from inside** (mirror of the GPU checks, minus `nvidia-smi`):
- `nproc` / `free -h` return the negotiated CPU/RAM.
- emptyDir scratch is writable (`touch /tmp/.t`).
- NFS store is mounted at the chosen path with models visible; the model-store mount is genuinely read-only (`touch /mnt/network-mount/.write-test` must fail).

**7. Hand over.** Give the exec and delete commands. `kubectl cp` (local ↔ pod data) is **only** performed when the user explicitly asks for it.

## Manifest template

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: test-pod-cpu-rvoelckner   # <base>-<username>; settle base with user, append $USER
  namespace: mf-llm-qa            # settle with user (default mf-llm-qa)
  labels:
    app: test-pod-cpu
    owner: rvoelckner             # username, for attribution/cleanup
spec:
  securityContext:                # default 47090 (all ns); option 2 = image default user, drop runAsUser
    runAsUser: 47090
    runAsNonRoot: true
    # fsGroup: 21655691           # only for live namespaces
  volumes:
    - name: model-store
      persistentVolumeClaim:
        claimName: mf-llm-qa-nonlive-nfs-llm-model   # settle with user
    - name: scratch
      emptyDir:
        sizeLimit: 50Gi           # node-local, wiped with the pod
  containers:
    - name: test-pod-cpu
      image: cr.mam.dev/internal/mamido/debian-slim:bookworm   # settle with user
      command: ["sleep"]
      args: ["infinity"]
      volumeMounts:
        - mountPath: /mnt/network-mount/   # default, settle with user
          name: model-store
          readOnly: true                   # RO default; rw only on explicit request
        - mountPath: /tmp                  # container root FS is read-only; emptyDir makes /tmp writable
          name: scratch
      resources:
        requests:
          memory: 8Gi                      # settle with user
          cpu: 1
        limits:
          memory: 16Gi
          cpu: 2
```

Note: this image is a slim Debian — no vLLM/triton. If the user wants to run something heavier, they supply their own image. No nodeSelector, no tolerations, no `nvidia.com/*` resources.

## Access & cleanup

```bash
kubectl --context=<ctx> -n <ns> exec -it <pod> -- /bin/bash   # or /bin/sh
kubectl --context=<ctx> -n <ns> cp <ns>/<pod>:<path> ./local  # only on explicit request
kubectl --context=<ctx> -n <ns> delete pod <pod>              # cleanup when done
```

## Pitfalls / warnings

- **Never scout for CPU capacity** — CPU is assumed always available. Doing so wastes time and is not the goal of this skill.
- **Namespace quota gates the deploy** even when nodes are free — check `requests.cpu=used/hard` for the chosen namespace before applying.
- **The model store is namespace-pinned** — mountable only from `mf-llm-qa`; the scout's `store:` column makes this visible.
- **The model store is shared multi-tenant infrastructure** — mounted **read-only** by default; any write-back requires an explicit user request to remount `rw`.
- **No rights where silent** — if a context shows 0 pod-create namespaces (e.g. `*lxa`, `infra-*`), don't plan there.
- **Prod is listed as-is** — no explicit opt-in gate; the env column distinguishes live namespaces.
- **No GPU anywhere** — no `nvidia.com/*` resources, no `nodeSelector`, no tolerations in the manifest. Presence of any of these means the CPU flow was leaked in from the GPU variant.
- **Default kubectl context is prod** — always pass `--context` explicitly.
- **Long-lived by default** — `sleep infinity`; only switch to a one-shot job if the user asks.
- **Network egress is out of scope** — don't set up egress testing unless the user brings it up.
- **Do not auto-copy local data** — `kubectl cp` only on explicit request.
