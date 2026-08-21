#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
    printf 'Usage: %s URL [CONCURRENCY]\n' "$0" >&2
    exit 2
fi

BASE_URL="${1%/}"
case "$BASE_URL" in http://*|https://*) ;; *) printf 'URL must start with http:// or https://\n' >&2; exit 2;; esac
REQUESTS="${2:-48}"
CONCURRENCY="$REQUESTS"
MAX_TOKENS=512
[[ "$CONCURRENCY" =~ ^[1-9][0-9]*$ ]] || { printf 'CONCURRENCY must be positive\n' >&2; exit 2; }
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vllm-benchmark.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
export BASE_URL REQUESTS CONCURRENCY MAX_TOKENS WORK_DIR

python3 - "$WORK_DIR/payload.json" <<'PY'
import json, sys, os
prompt = """Analyze this internal security-analysis platform as a senior systems engineer. It receives confidential documents, extracts entities and relationships, classifies security-relevant content, and produces auditable explanations. Discuss synchronous versus queued handling, TLS-terminating reverse proxies, six independent model replicas, routing, timeouts, retries, backpressure, GPU exhaustion, long contexts, client disconnects, partial responses, certificate rotation, metrics, alerts, and a concrete zero-interruption rollout checklist. Be precise and avoid generic advice."""
with open(sys.argv[1], "w") as f:
    json.dump({"model":"ensemble","messages":[{"role":"user","content":prompt}],"max_tokens":int(os.environ["MAX_TOKENS"]),"temperature":0.2,"stream":False}, f)
PY

run_request() {
    local id="$1"
    curl -skS --connect-timeout 15 --max-time 900 \
      -H 'Content-Type: application/json' --data-binary "@$WORK_DIR/payload.json" \
      -o "$WORK_DIR/response-$id.json" -w '%{http_code} %{time_total}\n' \
      "$BASE_URL/v1/chat/completions" >"$WORK_DIR/meta-$id.txt" 2>"$WORK_DIR/error-$id.txt" || true
}

printf 'Benchmark URL: %s\nRequests: %s, concurrency: %s, max_tokens: %s\n' "$BASE_URL" "$REQUESTS" "$CONCURRENCY" "$MAX_TOKENS"
START_NS="$(python3 -c 'import time; print(time.time_ns())')"
for ((first=1; first<=REQUESTS; first+=CONCURRENCY)); do
    last=$((first + CONCURRENCY - 1)); ((last > REQUESTS)) && last=$REQUESTS
    for ((id=first; id<=last; id++)); do run_request "$id" & done
    wait
done
END_NS="$(python3 -c 'import time; print(time.time_ns())')"

python3 - "$WORK_DIR" "$START_NS" "$END_NS" <<'PY'
import json, os, pathlib, sys
root=pathlib.Path(sys.argv[1]); wall=(int(sys.argv[3])-int(sys.argv[2]))/1e9; rows=[]
for i in range(1,int(os.environ["REQUESTS"])+1):
    meta=(root/f"meta-{i}.txt").read_text().strip().split(); status=int(meta[0]) if meta and meta[0].isdigit() else 0; latency=float(meta[1]) if len(meta)>1 else None; error=""; usage={}
    path=root/f"response-{i}.json"
    if path.exists() and path.stat().st_size:
        try:
            body=json.loads(path.read_text()); usage=body.get("usage") or {}
            if status==0: error=body.get("error",{}).get("message","invalid response")
        except Exception as exc: error=f"invalid JSON: {exc}"
    else: error=(root/f"error-{i}.txt").read_text().strip()
    rows.append((status,latency,int(usage.get("prompt_tokens") or 0),int(usage.get("completion_tokens") or 0),int(usage.get("total_tokens") or 0),error))
ok=[r for r in rows if r[0]==200 and not r[5]]; lat=sorted(r[1] for r in ok if r[1] is not None)
def pct(f): return lat[min(len(lat)-1,round((len(lat)-1)*f))] if lat else 0
pt=sum(r[2] for r in ok); ct=sum(r[3] for r in ok); tt=sum(r[4] for r in ok)
print(f"Successful: {len(ok)}/{len(rows)}"); print(f"Wall time: {wall:.2f} s"); print(f"Requests/s: {len(ok)/wall:.3f}" if wall else "Requests/s: n/a"); print(f"Prompt tokens: {pt}"); print(f"Completion tokens: {ct}"); print(f"Total tokens: {tt}"); print(f"Completion tokens/s: {ct/wall:.2f}" if wall else "Completion tokens/s: n/a"); print(f"Total tokens/s: {tt/wall:.2f}" if wall else "Total tokens/s: n/a")
if lat: print(f"Latency seconds: min={min(lat):.2f} p50={pct(.5):.2f} p95={pct(.95):.2f} max={max(lat):.2f}")
if len(ok)!=len(rows): sys.exit(1)
PY
