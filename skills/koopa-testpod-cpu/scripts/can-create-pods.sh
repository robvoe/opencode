#!/usr/bin/env bash
# koopa-testpod: report which contexts/namespaces the current kube user can CREATE PODS in.
# Reads only (kubectl get + auth can-i) - makes no changes.
# Analyzes RoleBindings/ClusterRoleBindings for the resolved user + groups, then verifies
# non-statically with `auth can-i` for a compact set of candidate namespaces.
set -euo pipefail
FILTER="${1:-}"   # optional context substring, e.g. intg | prod | all

python3 - "$FILTER" <<'PY'
import base64, json, os, re, subprocess, sys

sub = os.environ.get("KUBECTL_OIDC_CLIENT")  # unused; token resolved below
filter_arg = sys.argv[1]

CTXS = subprocess.run(["kubectl","config","get-contexts","-o","name"],
                      capture_output=True, text=True).stdout.split()
if filter_arg and filter_arg != "all":
    CTXS = [c for c in CTXS if filter_arg in c]

# resolve identity from the flattened kubeconfig (first context's exec plugin token)
def resolve_identity():
    try:
        r = subprocess.run(["kubectl","config","view","--flatten","-o","json"],
                           capture_output=True, text=True)
        d = json.loads(r.stdout)
        for u in d.get("users", []):
            ex = (u.get("user") or {}).get("exec") or {}
            if ex.get("command") != "kubectl-oidc_login":
                continue
            args = [ex["command"]] + ex.get("args", [])
            env = dict(os.environ)
            tok = subprocess.run(args, capture_output=True, text=True, env=env)
            if tok.returncode:
                continue
            j = json.loads(tok.stdout)
            token = (j.get("status") or {}).get("token", "")
            if not token:
                continue
            p = token.split(".")[1]
            p += "=" * (-len(p) % 4)
            info = json.loads(base64.urlsafe_b64decode(p))
            return info.get("preferred_username") or info.get("name") or info.get("sub"), info.get("groups") or []
    except Exception as e:
        return "?", ["?", str(e)]
    return "?", []

username, groups = resolve_identity()
print(f"# identity: {username}")
print(f"# groups: {', '.join(groups)}")
print(f"# contexts: {', '.join(CTXS)}")

def kub(ctx, *args):
    return subprocess.run(["kubectl","--context="+ctx, *args],
                          capture_output=True, text=True)

def subject_matches(s):
    kind = s.get("kind")
    name = s.get("name")
    if kind == "User" and name == username:
        return True
    if kind == "Group":
        g = name
        if ":" in g:
            g2 = g.split(":")[-1]
            if any(g2 == x or g2 in x for x in groups):
                return True
        if any(g == x or g in x or x in g for x in groups):
            return True
    return False

def rules_allow_pods(rules):
    for rl in rules:
        api = rl.get("apiGroups") or []
        if "policy" in api and not (":extensions" in str(api)):
            pass  # still check verbs below; keep simple
        res = rl.get("resources") or []
        verbs = rl.get("verbs") or []
        touch = (not res or "pods" in res or "*" in res) and \
                (verbs and ("create" in verbs or "*" in verbs or "admin" in verbs))
        if touch:
            return True
    return False

# ClusterRole rule lookup cache per context
cr_cache = {}
def cluster_role_rules(ctx, name):
    key = (ctx, name)
    if key in cr_cache:
        return cr_cache[key]
    r = kub(ctx, "get", "clusterrole", name, "-o", "json")
    cr_cache[key] = json.loads(r.stdout).get("rules", []) if r.returncode == 0 else []
    return cr_cache[key]

def role_rules(ctx, ns, name):
    r = kub(ctx, "-n", ns, "get", "role", name, "-o", "json")
    return json.loads(r.stdout).get("rules", []) if r.returncode == 0 else []

print("\n# cluster-scoped bindings granting pods-create (username/group match)")
for ctx in CTXS:
    r = kub(ctx, "get", "clusterrolebindings", "-o", "json")
    if r.returncode:
        continue
    for crb in json.loads(r.stdout)["items"]:
        subs = crb.get("subjects") or []
        if not any(subject_matches(s) for s in subs):
            continue
        rules = cluster_role_rules(ctx, crb.get("roleRef", {}).get("name", ""))
        allowed = rules_allow_pods(rules) if rules else None
        roles = []
        if rules:
            roles = [f"{res}:{','.join(v)}" for rl in rules for res in (rl.get('resources') or ['*']) for v in [rl.get('verbs') or []]]
        print(f"  {ctx:20s} CRB={crb.get('metadata',{}).get('name')} role={crb.get('roleRef',{}).get('name')} pods_create={'YES' if allowed else 'no' if rules is not None else '??'}")

print("\n# namespace bindings granting pods-create (username/group match)")
rows = []
for ctx in CTXS:
    r = kub(ctx, "get", "rolebindings", "-A", "-o", "json")
    if r.returncode:
        continue
    for rb in json.loads(r.stdout)["items"]:
        subs = rb.get("subjects") or []
        if not any(subject_matches(s) for s in subs):
            continue
        ns = rb["metadata"]["namespace"]
        rules = role_rules(ctx, ns, rb.get("roleRef", {}).get("name", ""))
        if not rules:
            continue
        if rules_allow_pods(rules):
            rows.append((ctx, ns, rb.get("roleRef", {}).get("name", "")))

seen = set()
for ctx, ns, role in rows:
    key = (ctx, ns)
    if key in seen:
        continue
    seen.add(key)
    # live verification
    v = kub(ctx, "-n", ns, "auth", "can-i", "create", "pods")
    ver = v.stdout.strip()
    print(f"  {ctx:20s} {ns:36s} role={role}  verify={ver}" + ("  <-- DENIED" if ver != "yes" else ""))
print("\n# summary")
print(f"  namespaces where create pods is bound: {len(seen)}")
PY
