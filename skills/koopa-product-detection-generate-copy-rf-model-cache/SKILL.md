---
name: koopa-product-detection-generate-copy-rf-model-cache
description: Use when a Roboflow inference server deployment on the koopa Kubernetes clusters (e.g. product-detection-rf / smartsearch-backend-product-detection-rf-any-live, image roboflow/roboflow-inference-server-cpu) must serve its model completely offline because the Roboflow API / inference-models registry is unreachable. Covers generating the model cache in a local Docker container using the exact same image pulled from the cluster's local registry mirror (never Docker Hub), copying the cache out of the container/VM while preserving relative symlinks, blindfolded local smoke-testing with zero internet egress, copying the cache to the shared model store (DGX / /export NFS) — optionally left to the user — verifying inside the running Kubernetes pod, repairing the runtime-compatibility hashing quirk (auto-resolution-cache / model_config.json hashes) when the pod computes different hashes than the origin, and restarting the pod for final offline verification. Use ONLY when this kind of offline model-cache restore for a Roboflow inference-server deployment is the goal.
---

# koopa-product-detection-generate-copy-rf-model-cache

Generate, smoke-test and deploy the **offline model cache** for a Roboflow inference server deployment on the koopa Kubernetes clusters so that the pod can start and infer with **zero network egress to Roboflow**. The Roboflow 1.x server refuses offline load unless the model cache (auto-resolution-cache + models-cache + shared-blobs) is pre-populated on the mounted model store and self-consistent with the pod's runtime.

This is a **guided, question-heavy process**. Ask the user often; never assume the environment (VM vs bare metal), the image version, the model ID, or whether to touch the shared model store.

## Model cache anatomy — what actually needs to exist

The server reads the model cache from `INFERENCE_HOME`, which defaults to **`MODEL_CACHE_DIR`** (see `inference_models/configuration.py` and `inference/core/env.py`). The cache directory must contain:

| Path (relative to MODEL_CACHE_DIR) | Purpose |
|---|---|
| `models-cache/v2-<model-slug>/<package_id>/model_config.json` | package manifest (not a symlink; plain file) |
| `models-cache/v2-<model-slug>/<package_id>/weights.onnx` | symlink -> `../../../shared-blobs/<md5 of weights>` |
| `models-cache/v2-<model-slug>/<package_id>/class_names.txt` | symlink -> `../../../shared-blobs/<md5>` |
| `models-cache/v2-<model-slug>/<package_id>/inference_config.json` | symlink -> `../../../shared-blobs/<md5>` |
| `shared-blobs/<md5>` | plain files, one per blob (weights ~38MB, small configs) |
| `auto-resolution-cache/<auto_negotiation_hash>.json` | resolution cache entry (the hash-keyed lookup) |
| `<model_id>/<version>/model_type.json` | legacy model-type marker, e.g. `prospekt-produkt-erkennung/3/model_type.json` |

**The symlinks must be relative** (`../../../shared-blobs/<md5>`) so the folder is portable. The `shared-blobs` names are the **md5 hashes** declared in `model_config.json`'s `package_artifacts`.

Key fact about auto-resolution cache: the entry's `resolved_files` array contains **absolute paths** — they must match the production mount path exactly, so the cache folder must land at exactly `<mount>/<MODEL_CACHE_DIR relative path>`.

## The hashing quirk (critical)

The auto-resolution cache is keyed by an `auto_negotiation_hash` = `sha256(json.dumps({...model+loading params..., "runtime_compatibility": {...}}, sort_keys=True))` where `runtime_compatibility` includes `onnxruntime_version`, `available_onnx_execution_providers`, `torch_version`, `os_version`, GPU details, etc. (`_runtime_compatibility_content` in `inference_models.models.auto_loaders.core`). The same model loaded on a **different runtime produces a different hash and misses the cache**.

Symptom: the pod logs `RetryError: Connectivity error ... GET /inference-models.roboflow.com ...` on `/model/add` even though the cache folder is present. This almost always means the origin (local Docker) runtime differs from the pod runtime — typically different `onnxruntime_version` and `available_onnx_execution_providers` set (e.g. local has `[AzureExecutionProvider, CPUExecutionProvider]` with onnxruntime 1.21.1, pod has `[CPUExecutionProvider, OpenVINOExecutionProvider]` with onnxruntime 1.21.0).

Note that the cache is additionally keyed with the `api_key` used at generation time, and the deployment may send a key per-request from the caller rather than setting a `ROBOFLOW_API_KEY` env in the pod. Use the same key for generation, smoke test, and in-pod load that the real workload will send.

**Hard rule — always use the cluster's local registry mirror, never Docker Hub.** Pull the exact image ref the deployment uses (e.g. `external.cr.mam.dev/roboflow/roboflow-inference-server-cpu:1.3.7`), because the underlying OS/runtime differs from Docker Hub's build (different `onnxruntime_version` / `available_onnx_execution_providers`), which changes the hashes and guarantees a cache miss in the pod. If the local registry is not pullable, **STOP and tell the user**: we only ever pull from the local registry for this reason, so we will not silently fall back to Docker Hub. Always verify inside the pod regardless; if the hashes still mismatch, repair them in-pod (see Step 5).

## Prerequisites

- `kubectl` with the cluster context (e.g. `be-prod-iz2-bap`), `docker` (detect the backend: colima / Docker Desktop / remote — see Step 1), SSH access to the model store node (e.g. an SSH alias like `dgx` and/or `dgx-node01` via `ProxyJump`).
- A test image (e.g. a catalog crop) and a way to send it. `scripts/smoke_test.py` uses `inference_sdk`: run it with the currently active python env (`VIRTUAL_ENV` / `CONDA_PREFIX` / `pdme` / `uv`), otherwise **ask the user which env to use**.
- Permissions to write to the mounted model store and to the pod (exec).

## Step 0 — Ask the user (gather everything up front)

Ask, in order, and confirm each answer before proceeding:

0. **Cache source** — does the live pod still hold a populated cache on the mounted store (e.g. downloaded before the network was cut)? If so, prefer copying that populated cache as the origin (assemble/bless it, then repack) rather than re-downloading — it is already runtime-consistent with the cluster. Otherwise generate fresh locally (Step 1, requires one-time egress).
1. **Model / deployment identity** — the deployment name (e.g. `product-detection-rf` / `smartsearch-backend-product-detection-rf-any-live`), namespace, and cluster context. Resolve the **model ID** (e.g. `prospekt-produkt-erkennung/3`) yourself in this order: (1) look in the deployment/code for `MODEL_CACHE_DIR`/`MODEL_ID` env or labels, (2) read `ROBOFLOW_MODEL_ID` from the project's `.env` if it points at it, (3) only if it can't be found, ask the user — as an alternative to asking, use the Roboflow API (with the user's key) to list all models they own and offer suggestions.
2. **Image version & registry** — find it **yourself** from the deployment first (`kubectl get deploy ... -o yaml | grep image:` or `app.kubernetes.io/version` label), then **confirm with the user**. The image must come from the **cluster's local registry mirror** (never Docker Hub); if the mirror isn't pullable locally, stop and explain why (see "hashing quirk").
3. **Environment** — is the local machine a VM under macOS (files may need copying out of the VM; ask how/where), bare-metal, or a remote host? Detect the docker backend (`docker context ls`) and say which copy-out mechanics apply.
4. **MODEL_CACHE_DIR & mount path in the cluster** — read from the deployment env; the cache must land at `<mount>/<MODEL_CACHE_DIR path>`.
5. **Model store / DGX copy** — `ASK, don't assume`: does the user want you to copy to the shared model store, or do they do it themselves? If you, ask for the exact target path (e.g. `user@node:/export/.../prospekt-produkt-erkennung-3`) and the pod user/group (uid/fsGroup, typically uid 1000, group 21655691).
6. **API key** — read `ROBOFLOW_API_KEY` from the environment/`.env` if present and use that; only ask if it's missing. Never echo the key in commands or output (use a shell variable).

## Step 1 — Generate the model cache in a local Docker container

First detect the docker backend to know how "copying out of the VM" works: `docker context ls` → Docker Desktop (Linux VM on mac), **colima** (Linux VM, `colima status` tells you its arch, e.g. `aarch64`), or a **remote/SSH context** (files live on the remote host). This matters because the VM's arch can differ from the cluster's x86_64 pod, changing `onnxruntime_version`/execution providers and therefore the hashes — stay aware, and never fall back to Docker Hub.

Run a local container of the **same image as the deployment** (cluster registry mirror) with one-time network access for the download, mount a fresh host dir as the cache, and warm the model. Bypass the platform mismatch if the VM has a different arch than the registry image (e.g. `--platform linux/amd64` on an aarch64 colima, if emulation/QEMU is available) so the runtime matches the pod's — otherwise plan on the in-pod hash repair (Step 5):

```bash
CACHE_HOST=/abs/path/to/model_<version>          # created by you, will be copied out
docker run -d --name rf-cache-gen \
  -p 9001:9001 \
  -v "$CACHE_HOST:/opt/models" \
  -e "MODEL_CACHE_DIR=/opt/models" \
  -e "USER=1000" -e NUM_WORKERS=1 \
  -e ALLOW_CUSTOM_PYTHON_EXECUTION_IN_WORKFLOWS=false \
  -e TELEMETRY_USE_PERSISTENT_QUEUE=false \
  -e MPLCONFIGDIR=/tmp/matplotlib -e XDG_CACHE_HOME=/tmp/.cache \
  <cluster-registry>/roboflow/roboflow-inference-server-cpu:<version>
```

Then trigger `POST /model/add` (JSON body `{"model_id": "...", "api_key": "..."}`) so the model is downloaded and the cache is written under `/opt/models` (auto-resolution-cache/, models-cache/, shared-blobs/, `<model>/<version>/model_type.json`). Optionally also do one inference to confirm the cache is complete. The container has network **only** for this warm-up step; every later step (smoke, deploy, verify) is offline.

**Copying out of the VM per backend**:
- **colima / Docker Desktop on macOS**: bind-mount a real macOS host dir (`-v "$CACHE_HOST:/opt/models"` above) so the cache is written straight to the host — verify symlinks survived on the macOS side (`ls -l` shows `-> ../../../shared-blobs/...`), repair if the generator wrote absolute links (see below).
- **remote/SSH context**: cache lives on the remote host; `rsync -a`/`scp` (or `docker cp` from the stopped container) to the local host — `rsync -a` preserves symlinks; **do NOT use `-L`**.

**Repair relative symlinks** for portability, if the generator wrote absolute links matching the container path: rewrite each link under `models-cache/.../<package>/` as `../../../shared-blobs/<md5>` (verify with `readlink -f`), and confirm each `md5` matches `model_config.json`.

## Step 2 — Blindfolded local smoke test (offline, zero egress)

Before touching the cluster, prove the cache loads offline. Run a container with Roboflow hosts blackholed and the cache mounted at the exact production path:

```bash
docker run -d --name rf-smoke \
  -p 9001:9001 \
  --add-host api.roboflow.com:203.0.113.1 \
  --add-host repo.roboflow.com:203.0.113.2 \
  --add-host hub.roboflow.com:203.0.113.3 \
  --add-host detect.roboflow.com:203.0.113.4 \
  --add-host inference-models.roboflow.com:203.0.113.1 \
  -v "<cache-host-dir>:/opt/models/<MODEL_CACHE_DIR relative path>" \
  -e "MODEL_CACHE_DIR=/opt/models/<MODEL_CACHE_DIR relative path>" \
  ... (same flags as Step 1) ...
  <registry>/roboflow/roboflow-inference-server-cpu:<version>
```

**Important**: mount at the exact `MODEL_CACHE_DIR` path the cluster uses — the `resolved_files` in the auto-resolution-cache entry are absolute and must resolve. Use a **fresh copy** of the cache for each smoke run: the server **deletes** an auto-resolution-cache entry it deems unusable, and a failed first run can invalidate the cache before a corrected run re-tests.

Run `scripts/smoke_test.py load+infer` (or curl) against the blackholed container: `/model/add` must succeed and inference must return detections. Run it with the **active python env** (`VIRTUAL_ENV`/`CONDA_PREFIX`/pdm/uv); if none, ask the user which env has `inference_sdk`. Pass the key via `$ROBOFLOW_API_KEY` (from env/`.env`) — never inline it: `python scripts/smoke_test.py --url http://localhost:9001 --api-key "$ROBOFLOW_API_KEY" --model-id <model>/<version> --image <test.jpg>`. Confirm in the container logs that there were **zero** `Connectivity error` / `RetryError` / `get_one_page_of_model_metadata` attempts.

If smoke fails with "Connectivity error": the cache is being missed — check hash mismatch (Step 0/#quirk) and/or mount path / symlinks / permissions.

## Step 3 — Copy to the shared model store (optional — ask first)

Ask the user who copies it. If they want you to: **first back up any existing cached model** on the store (don't overwrite a possibly-working cache in place) — e.g. `mv <target> <target>.bak-$(date +%Y%m%d-%H%M%S)` or `tar` it away, then:

```bash
rsync -a --itemize-changes <cache-dir>/ <user>@<node>:<target>/   # preserve symlinks
# fix group so the pod (uid 1000, fsGroup e.g. 21655691) can read:
ssh <user>@<node> 'chgrp -R <fsgroup> <target> && find <target> -type d -exec chmod 2775 {} \; && find <target> -type f -exec chmod g+r,o+r {} \;'
```

`chgrp` only works if your SSH user is a member of the target group. Verify inside the store that symlinks resolve (`readlink -f`) and md5 blobs are intact.

## Step 4 — Verify in the running Kubernetes pod

`kubectl exec` into the pod's server container, confirm the structure and readability as the pod user, and check the current state:

```bash
kubectl exec <pod> -c <server-container> -- id          # expect uid 1000, fsGroup group present
kubectl exec <pod> -c <server-container> -- sh -c '
  find <MODEL_CACHE_DIR> ...; stat -c "%a %u:%g" ...'
```

Then trigger load+infer inside the pod (no port-forward needed; hit `127.0.0.1:9001`):
- `POST /model/add` `{"model_id": "...", "api_key": "..."}` → expect `200`.
- `POST /infer/object_detection` with a test image → expect predictions.
- Confirm **zero** network attempts in the pod logs (`get_one_page_of_model_metadata`, `RetryError`, `Connectivity error`). (Note: a benign `Active Learning configuration` "Could not connect" line at startup is normal and unrelated.)

## Step 5 — Repair the hashing quirk (only if the pod misses the cache)

If `/model/add` in the pod still 500s with `Connectivity error` / `RetryError`, the pod computes a **different `auto_negotiation_hash`** than the cache expects. Repair by regenerating the cache metadata **in the pod** so all hashes are computed with the pod's own runtime:

1. Capture the pod's computed hashes by intercepting the cache-load entry point:
   ```python
   # run inside pod as the server python
   import os, inspect, inference_models.models.auto_loaders.core as core
   os.environ.setdefault("INFERENCE_HOME", os.environ["MODEL_CACHE_DIR"])
   sig = inspect.signature(core.attempt_loading_model_with_auto_load_cache)
   def wrap(*args, **kw):
       b = sig.bind_partial(*args, **kw); b.apply_defaults()
       print("auto_neg=", b.arguments.get("auto_negotiation_hash"))
       print("offline=", b.arguments.get("expected_offline_compatibility_hash"))
       return None
   core.attempt_loading_model_with_auto_load_cache = wrap
   from inference.core.models.inference_models_adapters import InferenceModelsObjectDetectionAdapter
   InferenceModelsObjectDetectionAdapter(model_id="<model>/<version>", api_key="<key>", device="cpu")
   ```
   (Replicate the server's exact adapter call; do not invent parameters — run it the way the deployment does.)
2. Compute the pod's `runtime_compatibility_hash` (`_runtime_compatibility_hash(x_ray_runtime_environment())`).
3. Rewrite `model_config.json`: set `runtime_compatibility_hash` = pod's value (JSON as loaded by `parse_model_config`).
4. Compute the new `manifest_content_hash = hash_dict_content(raw_config)` and write a new `auto-resolution-cache/<auto_neg_hash>.json` with `offline_compatibility_hash`/`package_manifest_hash`/etc. matching the pod; delete the stale entry.
5. `chmod g+w` the cache files first so the pod user can write them, and `chgrp` to the fsGroup via the store/SSH.
6. Re-test in-pod (`/model/add` → 200, inference works, zero network).
7. Mirror the corrected metadata back into the local cache dir and re-pack/re-upload if one was produced.

## Step 6 — Restart the pod and final offline verification

Once verified in-session: `kubectl rollout restart deployment/<name>` and wait for rollout. Then re-run the in-pod load+infer check against the **new** pod and confirm still `200` + predictions + **zero** network attempts after restart. Remove the test image/copies you created in the pod.

## Pitfalls

- **Cache is deleted on invalidation.** The server removes an unusable `auto-resolution-cache/*.json`. Always smoke-test on a fresh copy, and never mutate the live store in-place with a possibly-wrong cache.
- **Mount path must match production exactly** (`resolved_files` are absolute).
- **Runtime mismatch breaks the cache** — generate with the cluster's image/registry when possible; verify in-pod anyway and repair hashes in-pod if needed.
- **Symlinks must be relative** and point `../../../shared-blobs/<md5>`; verify md5s against `model_config.json`.
- **Permissions**: the pod runs as uid 1000 with an fsGroup; files must be group-readable (and group-writable if the repair step rewrites them in place). `chgrp` needs membership in the target group.
- **File ownership after in-pod writes** becomes `1000:<fsgroup>` naturally — that is fine and even preferred.
- **Pod name changes on restart** — get the pod via `-l app.kubernetes.io/instance=<name>` rather than hardcoding.
