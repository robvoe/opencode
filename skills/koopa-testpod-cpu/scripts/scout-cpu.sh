#!/usr/bin/env bash
# koopa-testpod-cpu: survey CPU-only test-pod placement across kubernetes contexts.
# Reads only (kubectl get) - makes no changes.
# Usage: scripts/scout-cpu.sh [prod|intg|all] [namespace-substring]
#   filter  prod | intg | all (default: all) - which contexts to scan,
#           so `scout-cpu.sh` with no args scans every context at once
#   ns      optional 2nd arg: only report namespaces whose name contains this substring
set -euo pipefail

FILTER="${1:-all}"
NS_SUB="${2:-}"

CTXS=$(kubectl config get-contexts -o name)
if [ "${FILTER}" != "all" ]; then
  CTXS=$(printf '%s\n' "${CTXS}" | grep -E "${FILTER}" || true)
fi
if [ -z "${CTXS}" ]; then
  echo "no contexts matching '${FILTER}'" >&2
  exit 1
fi

export NS_SUB
python3 - "${CTXS}" <<'PY'
import json, os, re, subprocess, sys

ns_sub = os.environ.get("NS_SUB", "").strip()
ctxs = [c for c in sys.argv[1].split() if c]

def kub(ctx, *args):
    return subprocess.run(["kubectl", "--context=" + ctx, *args],
                          capture_output=True, text=True)

def to_cpu(v):
    m = re.fullmatch(r"(\d+)(m)?", v or "0")
    if not m: return 0.0
    n = int(m.group(1))
    return n / 1000.0 if m.group(2) else float(n)

def to_gib(v):
    m = re.match(r"(\d+(?:\.\d+)?)([KMG]i)?$", str(v))
    if not m: return 0.0
    n = float(m.group(1)); u = m.group(2)
    if u == "Gi": return n
    if u == "Mi": return n / 1024.0
    if u == "Ki": return n / 1024.0 / 1024.0
    return n / 1024.0 / 1024.0 / 1024.0  # bare number = bytes in k8s Quantity

def gib(v):
    return f"{to_gib(v):.1f}Gi"

def requested_per_node(ctx):
    """Sum of requests.cpu / requests.memory across all pods, grouped by node."""
    r = kub(ctx, "get", "pods", "-A", "-o", "json")
    if r.returncode: return {}
    out = {}
    for p in json.loads(r.stdout)["items"]:
        node = p.get("spec", {}).get("nodeName")
        if not node: continue
        for c in p.get("spec", {}).get("containers", []):
            req = c.get("resources", {}).get("requests", {})
            d = out.setdefault(node, dict(cpu=0.0, mem=0.0))
            d["cpu"] += to_cpu(req.get("cpu", "0"))
            d["mem"] += to_gib(req.get("memory", "0"))
    return out

# ---- per-context / per-node summary ----
rows = []          # (ctx, node, alloc_cpu, free_cpu, mem_alloc, labels)
ctx_sum = {}
for ctx in ctxs:
    r = kub(ctx, "get", "nodes", "-o", "json")
    if r.returncode:
        print(f"## {ctx}: ERROR {r.stderr.strip()}", file=sys.stderr)
        continue
    used = requested_per_node(ctx)
    t_alloc = t_free = 0.0
    nodes = []
    for n in json.loads(r.stdout)["items"]:
        a = n.get("status", {}).get("allocatable", {})
        alloc = to_cpu(a.get("cpu", "0"))
        free = alloc - used.get(n["metadata"]["name"], dict(cpu=0))["cpu"]
        t_alloc += alloc
        t_free += max(free, 0.0)
        nodes.append((n["metadata"]["name"], alloc, max(free, 0.0),
                      gib(a.get("memory", "")),
                      ",".join(sorted(n.get("metadata", {}).get("labels", {}).get("kubernetes.io/role", "").split()) or "-")))
    ctx_sum[ctx] = dict(n=len(nodes), alloc=t_alloc, free=t_free, nodes=nodes)

print(f"# koopa CPU pod placement  contexts scanned: {', '.join(ctxs)}")
w_ctx = max([len("context")] + [len(c) for c in ctxs])
print(f"{'context'.ljust(w_ctx)}  nodes  alloc-cpu  free-cpu  largest-free-node")
for ctx in ctxs:
    s = ctx_sum.get(ctx)
    if not s:
        print(f"{ctx.ljust(w_ctx)}  ERROR")
        continue
    best = max(s["nodes"], key=lambda x: x[2], default=("", 0, 0, "-", "-"))
    print(f"{ctx.ljust(w_ctx)}  {s['n']:3d}    {s['alloc']:7.1f}   {s['free']:7.1f}   {best[0]} (free {best[2]:.1f}c, mem {best[3]})")

print("\n# per-node detail")
for ctx in ctxs:
    s = ctx_sum.get(ctx)
    if not s: continue
    print(f"## {ctx}")
    for name, alloc, free, mem, role in s["nodes"]:
        print(f"  {name:45s} alloc {alloc:6.1f}c  free {free:6.1f}c  mem {mem:>7s}  role={role}")

# ---- per-namespace CPU/memory quota headroom + model store ----
print("\n# per-namespace  (NS CPU quota headroom: requests.cpu=free-of-hard budget  |  mem  |  model store)")
for ctx in ctxs:
    pvc_ns = {}
    pr = kub(ctx, "get", "pvc", "-A", "-o", "json")
    if pr.returncode == 0:
        for pvc in json.loads(pr.stdout)["items"]:
            if "ReadWriteMany" not in pvc.get("spec", {}).get("accessModes", []): continue
            pvc_ns.setdefault(pvc["metadata"]["namespace"], []).append(
                f"{pvc['metadata']['name']}({pvc['status'].get('phase','?')})")
    r = kub(ctx, "get", "resourcequotas", "-A", "-o", "json")
    if r.returncode: continue
    quotas = {}
    for q in json.loads(r.stdout)["items"]:
        ns = q["metadata"]["namespace"]
        if ns_sub and ns_sub not in ns: continue
        if ns_sub == "" and re.search(r"^(kube-|openshift-|default$|gatekeeper)", ns): continue
        used = q.get("status", {}).get("used", {})
        hard = q.get("spec", {}).get("hard", {})
        d = quotas.setdefault(ns, dict(cpu_hard="?", mem_hard="?", lines=[]))
        if hard.get("requests.cpu"):
            d["cpu_hard"] = hard["requests.cpu"]
            u = to_cpu(used.get("requests.cpu", "0"))
            d["lines"].append(f"requests.cpu free={to_cpu(hard['requests.cpu'])-u:g}/{hard['requests.cpu']}")
        if hard.get("requests.memory"):
            d["mem_hard"] = hard["requests.memory"]
            d["lines"].append(f"requests.memory free={to_gib(hard['requests.memory'])-to_gib(used.get('requests.memory','0')):.0f}Gi/{hard['requests.memory']}")
    for ns in sorted(quotas):
        d = quotas[ns]
        store = ", ".join(pvc_ns.get(ns, [])) or "NO RWX PVC"
        print(f"  {ctx:22s} {ns:28s} " + "  ".join(d["lines"]) + f"  store: {store}")
PY
