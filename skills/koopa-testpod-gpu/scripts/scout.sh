#!/usr/bin/env bash
# koopa-testpod: survey the GPU landscape across koopa's GPU-bearing kubernetes clusters.
# Reads only (kubectl get) - makes no changes.
# The user picks the environment only (intg|prod); clusters are auto-derived from the
# koopa naming schema: be-{intg|prod}-iz{1|2}-{bs|bap|lxa}.
# Usage: scripts/scout.sh [intg|prod] [namespace]
#   mode      intg (QA, default) or prod
#   namespace optional 2nd arg: restrict namespace-quota headroom report to one namespace
set -euo pipefail

MODE="${1:-intg}"
NS_FILTER="${2:-}"

# koopa naming schema: stack-be -> be, fe, infra ; env -> intg|prod ; zone -> iz1|iz2 ; site -> bs|bap|lxa
MODE_RE="^be-.*${MODE}"
CTXS=$(kubectl config get-contexts -o name | grep -E "${MODE_RE}" || true)
if [ -z "${CTXS}" ]; then
  echo "no be-*${MODE}* contexts found" >&2
  exit 1
fi

export MODE NS_FILTER
python3 - "${CTXS}" <<'PY'
import json, os, re, subprocess, sys

mode = os.environ["MODE"]
ns_filter = os.environ.get("NS_FILTER", "").strip()
ctxs = [c for c in sys.argv[1].split() if c]

CLASS_ORDER = ["T4", "A100 full", "A100 MIG", "H100 MIG"]
STATIC = {
    "T4":       dict(lbl="nvidia.com/gpu.tesla-t4", res="nvidia.com/gpu",        vram="15 GiB", per="1-2", env="64-104c / 374 Gi, or 256c / 753 Gi", taint="none (open pool)"),
    "A100 full":dict(lbl="nvidia.com/gpu.ampere-a100", res="nvidia.com/gpu",     vram="~80 GiB", per="1",   env="256c / 753 Gi",                    taint="yes"),
    "A100 MIG": dict(lbl="nvidia.com/gpu.ampere-a100", res="nvidia.com/mig-7g.40gb", vram="40 GiB", per="1", env="256c / 753 Gi",                 taint="yes"),
    "H100 MIG": dict(lbl="nvidia.com/gpu.hopper-h100", res="nvidia.com/mig-7g.94gb", vram="94 GiB", per="2", env="128c / 374 Gi",                 taint="yes"),
}

def kub(ctx, *args):
    return subprocess.run(["kubectl", "--context=" + ctx, *args],
                          capture_output=True, text=True)

def mi_to_gib(v):
    m = re.match(r"(\d+)([KMG]i)?$", v)
    if not m: return v
    n = int(m.group(1)); u = m.group(2) or ""
    if u == "Gi": return f"{n}Gi"
    if u == "Mi": return f"{n/1024:.1f}Gi"
    if u == "Ki": return f"{n/1024/1024:.1f}Gi"
    return f"{n}{u}"

def classify(node):
    l = node.get("metadata", {}).get("labels", {})
    a = node.get("status", {}).get("allocatable", {})
    if "nvidia.com/gpu.tesla-t4" in l:    return "T4", "nvidia.com/gpu"
    if "nvidia.com/gpu.hopper-h100" in l: return "H100 MIG", "nvidia.com/mig-7g.94gb"
    if "nvidia.com/gpu.ampere-a100" in l:
        if any(k.startswith("nvidia.com/mig") for k in a):
            return "A100 MIG", "nvidia.com/mig-7g.40gb"
        return "A100 full", "nvidia.com/gpu"
    return None, None

def used_per_node(ctx):
    r = kub(ctx, "get", "pods", "-A", "-o", "json")
    if r.returncode: return {}
    out = {}
    for p in json.loads(r.stdout)["items"]:
        node = p.get("spec", {}).get("nodeName")
        if not node: continue
        for c in p.get("spec", {}).get("containers", []):
            req = (c.get("resources", {}).get("limits")
                   or c.get("resources", {}).get("requests") or {})
            for k, v in req.items():
                if k.startswith("nvidia.com/"):
                    try: n = int(v)
                    except Exception: continue
                    out.setdefault(node, {})
                    out[node][k] = out[node].get(k, 0) + n
    return out

def iz_of(ctx):
    m = re.search(r"iz(\d+)", ctx)
    return "iz" + m.group(1) if m else ctx

board = {c: dict(total=0, free=0, ctxs=set(), nodes=[]) for c in CLASS_ORDER}
details = []

for ctx in ctxs:
    r = kub(ctx, "get", "nodes", "-o", "json")
    if r.returncode:
        print(f"## {ctx}: ERROR {r.stderr.strip()}", file=sys.stderr)
        continue
    used = used_per_node(ctx)
    for n in json.loads(r.stdout)["items"]:
        cls, key = classify(n)
        if not cls: continue
        a = n.get("status", {}).get("allocatable", {})
        try: alloc = int(a.get(key, 0))
        except Exception: alloc = 0
        name = n["metadata"]["name"]
        used_n = int(used.get(name, {}).get(key, 0))
        taints = [t["key"] for t in n["spec"].get("taints", [])]
        st = f"{name} ({alloc-used_n}/{alloc} free)"
        board[cls]["total"] += alloc
        board[cls]["free"]  += max(alloc - used_n, 0)
        board[cls]["ctxs"].add(iz_of(ctx))
        board[cls]["nodes"].append(f"{ctx}:{name} FREE={alloc-used_n}/{alloc} cpu={a.get('cpu')} mem={mi_to_gib(a.get('memory',''))}" + (f" taint={','.join(taints)}" if taints else ""))

# ---- GPU-centric board: columns are GPU classes ----
cols = CLASS_ORDER
rows = []
def add(name, getter):
    rows.append([name] + [getter(c) for c in cols])
add("Node label",        lambda c: STATIC[c]["lbl"])
add("Resource to request",lambda c: STATIC[c]["res"])
add("VRAM per allocation",lambda c: STATIC[c]["vram"])
add("Allocations/node",  lambda c: STATIC[c]["per"])
add("Machine envelope",  lambda c: STATIC[c]["env"])
add("Reservation taint", lambda c: STATIC[c]["taint"])
add("Beds in use",         lambda c: f"{board[c]['total'] - board[c]['free']}/{board[c]['total']}")
add("Cluster(s)",        lambda c: " + ".join(sorted(board[c]["ctxs"])) or "-")

widths = [len("Attribute")]
for i, c in enumerate(cols):
    widths.append(max([len(c)] + [len(r[i+1]) for r in rows]))
def fmt(cells):
    return "  ".join(c.ljust(w) for c, w in zip(cells, widths)).rstrip()

# Plain aligned output - the agent renders this as a markdown grid table for the user.
print(f"# koopa GPU board  mode={mode} (QA=intg / live=prod)  clusters: {', '.join(ctxs)}")
print(fmt(["Attribute"] + cols))
for r in rows:
    print(fmt(r))
if all(board[c]["total"] == 0 for c in cols):
    print("(no GPU nodes found)")

# ---- per-node detail ----
key_bylabel = {c: STATIC[c]["res"] for c in CLASS_ORDER}
print("\n# per-node detail")
for c in CLASS_ORDER:
    if board[c]["nodes"]:
        print(f"## {c}")
        for d in board[c]["nodes"]:
            print("  " + d)

# ---- per-namespace model store (RWX NFS PVC) + GPU quota headroom ----
print("\n# per-namespace (model store = RWX NFS PVC  |  GPU quota headroom)")
print("  note: a static NFS PV is pinned by claimRef to its namespace - a store can only be mounted in the namespace that holds it")
for ctx in ctxs:
    pr = kub(ctx, "get", "pvc", "-A", "-o", "json")
    pvc_ns = {}
    if pr.returncode == 0:
        for pvc in json.loads(pr.stdout)["items"]:
            if "ReadWriteMany" not in pvc.get("spec", {}).get("accessModes", []): continue
            pvc_ns.setdefault(pvc["metadata"]["namespace"], []).append(
                f"{pvc['metadata']['name']}({pvc['status'].get('phase','?')})")
    r = kub(ctx, "get", "resourcequotas", "-A", "-o", "json")
    if r.returncode: continue
    for q in json.loads(r.stdout)["items"]:
        ns = q["metadata"]["namespace"]
        if ns_filter and ns_filter not in ns: continue
        if ns_filter == "" and not re.search(r"llm", ns, re.I): continue
        store = ", ".join(pvc_ns.get(ns, [])) or "NO MODEL-STORE PVC"
        used = q.get("status", {}).get("used", {})
        hard = q.get("spec", {}).get("hard", {})
        bits = []
        for k in used:
            if k.startswith("requests.nvidia.com") and hard.get(k, 0) != 0:
                bits.append(f"{k.replace('requests.','')}={used.get(k)}/{hard.get(k,'?')}")
        if not bits and "NO MODEL-STORE" in store: continue
        print(f"  {ctx:22s} {ns:28s} store: {store}")
        if bits:
            print(f"  {'':22s} {'':28s} quota: " + "  ".join(bits))
PY
