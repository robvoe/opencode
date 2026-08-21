---
name: dgx-vllm-nginx-deployment
description: Use when deploying, scaling, verifying, benchmarking, or cleaning up one or more vLLM model replicas on DGX behind an nginx TLS-terminating load balancer; supports automatic deployment and structured manual instructions, dynamic GPU/port discovery, local vision verification, Kong checks, and direct-vs-LB benchmarking. Use ONLY for DGX vLLM/nginx deployments.
---

# DGX vLLM + nginx deployment

Use this skill only for DGX deployments of vLLM replicas behind an nginx load
balancer. The default operating mode is assistant-executed deployment, but the
user may request structured manual instructions instead.

## Mandatory workflow

1. Load `<skilldir>/manual-deployment.md` before any deployment or manual
   instructions. It is an active procedure dependency, not a passive copy.
2. Confirm that `SKILL.md`, the runbook, scripts, and config template agree.
   Stop on a mismatch; do not silently choose one artifact.
3. Use `/grilling`, asking one decision at a time and giving a recommendation.
4. Ask for the GPU count; never assume it. Recommend 4 GPUs after discovery,
   but wait for explicit confirmation.
5. Discover the target worker and available GPUs through Slurm. Use an
   explicitly named node when supplied; never hardcode node 2.
6. Fetch the current Confluence User Port mappings. Use the authenticated
   user's range as the source of truth and reserve one model port per confirmed
   GPU. Do not copy other users' ranges into notes or skill files.
7. Ask for or confirm the model, model/cache path, vLLM image, and model-specific
   flags. Offer the validated Qwen3.8 profile in
   `<skilldir>/profiles/qwen3.8.md`, but require confirmation even for it.
8. For another model, grill each model-specific parameter separately. A user
   supplied vLLM command is allowed, but inspect it, substitute only confirmed
   per-replica values, and verify it on one isolated replica before reuse.
9. Ask for certificate and key paths. Never hardcode them. Validate format,
   matching key, readability, hostname, expiry, and TLS policy.
10. Validate image pullability, model/cache existence, vLLM arguments, GPU
    visibility, unique ports, and certificate paths before GPU allocation.
11. Render all runtime artifacts into a unique volatile directory on both head
    and worker nodes:
    `/tmp/<user>/<skill-name>-<deployment-id>/`.
12. Never modify this skill folder. Never overwrite an existing runtime config
    in place: preserve it in a timestamped backup under the deployment's
    volatile directory, render a new file, validate it, and ask before install.
13. Ask once for confirmation after presenting the complete deployment plan.
    Cleanup and restart operations require separate confirmations.
14. Launch one TP=1 model replica per confirmed GPU, each in its own clearly
    named window in the user's existing attached/default tmux session.
15. Verify the first replica before fan-out. On any failure, stop and show the
    failed replica/logs; ask whether to retry, reduce the topology, or abort.
16. Launch the remaining replicas only after the first is healthy.
17. Verify one direct model port only if the user has a local SSH forward for
    it. Ask for that forward when needed; do not create SSH forwards silently.
18. Verify the local vision fixture as a base64 data URI. DGX has no internet
    egress; never send a remote image URL.
19. Render and validate nginx with the actual image, mounts, certificate paths,
    and `nginx -t` before install. Use a shared upstream `zone` so multiple
    nginx workers share balancing state.
20. Start nginx only after every requested model replica is healthy, in a
    visible window in the same default tmux session.
21. Verify every model port, nginx `/v1/models`, non-streaming chat, streaming
    SSE, vision, the Kong URL, and the benchmark.
22. Use `<skilldir>/benchmark-vllm.sh` for direct-vs-LB measurements. Its
    interface is `benchmark-vllm.sh URL [CONCURRENCY]`; default concurrency is
    48 and the request count equals concurrency.
23. Report success rate, request/token throughput, latency min/p50/p95/max,
    and interpret direct-vs-LB results under the tested concurrency.

## Modes

- `deploy`: run the complete workflow above after grilling and confirmation.
- `manual`: perform read-only discovery and preflight, then load the runbook
  and print concrete resolved commands. Do not mutate anything.
- `status`: inspect only resources created or identified in the current session.
- `cleanup`: list matching current-session windows, jobs, ports, nginx, and
  temporary files; ask separately before stopping jobs, closing windows, or
  deleting files. Never infer ownership from ports alone.
- `benchmark`: run `<skilldir>/benchmark-vllm.sh` for a supplied URL and
  optional concurrency.

## Runtime rules

- DGX control happens from the head node through Slurm/Pyxis/enroot and tmux.
- Use versioned images; never silently replace a version with `latest`.
- Use explicit pyxis registry syntax such as
  `registry.example#/path/image:tag`. Do not silently rewrite registry hosts.
- Do not mirror images to DGX Harbor. Validate and pull the explicit image
  registry instead. The tested nginx image is
  `external.cr.mam.dev#/library/nginx:1.31.4`.
- Model replicas use plain HTTP on private per-user ports when nginx terminates
  TLS. nginx mounts the user-supplied certificate and key read-only.
- Use one tmux window per replica and one nginx window, all in the user's
  existing attached/default session. Discover the session dynamically; do not
  assume a numeric session target.
- Keep large model caches at validated user paths. Do not copy them into the
  volatile deployment directory.
- A supplied command is never copied blindly: inspect it, substitute only
  port/GPU/path values explicitly approved, then verify one replica.

## Companion artifacts

- Procedure: `<skilldir>/manual-deployment.md`
- Qwen3.8 profile: `<skilldir>/profiles/qwen3.8.md`
- Replica launcher: `<skilldir>/run-vllm-replica.sh`
- In-container serving template: `<skilldir>/serve-vllm-replica.sh`
- nginx launcher: `<skilldir>/run-nginx-lb.sh`
- nginx template: `<skilldir>/nginx.conf.tmpl`
- Verification helper: `<skilldir>/verify-deployment.sh`
- Benchmark: `<skilldir>/benchmark-vllm.sh`
- Vision fixture: `<skilldir>/assets/vision-fixture.jpg`

## Lessons encoded

- A six-GPU load balancer means six independent TP=1 replicas, not one TP=6
  process. Separate jobs isolate failures and make nginx useful.
- Nginx upstream state must be shared with `zone vllm 64k`; without it, each
  worker can repeatedly select the first peer and make a multi-replica test
  appear unbalanced.
- Use generated files for JSON and commands instead of fragile nested shell
  quoting through `tmux send-keys`.
- Validate the config file actually mounted into the running container; a
  locally edited file is not proof that nginx loaded it.
- Verify fresh request output rather than counting unbounded tmux scrollback.
- The direct reverse-proxy URL may be unavailable while the Kong URL works;
  verify the exact user-provided endpoint and report each path independently.
