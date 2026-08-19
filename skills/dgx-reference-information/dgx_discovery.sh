#!/usr/bin/env bash
set -u -o pipefail

json() {
    python3 -c 'import json,sys; print(json.dumps(json.loads(sys.stdin.read()), separators=(",", ":")))'
}

emit() {
    printf '%s\n' "$1" | json
}

module load slurm/slurm/23.02.8 >/dev/null 2>&1 || true

mapfile -t nodes < <(sinfo -N -h -o '%N' 2>/dev/null | sort -u)
is_worker() {
    local candidate
    for candidate in "${nodes[@]}"; do
        [ "$candidate" = "$1" ] && return 0
    done
    return 1
}

for node in "${nodes[@]}"; do
    detail=$(scontrol show node "$node" 2>/dev/null || true)
    state=$(printf '%s\n' "$detail" | sed -n 's/.*State=\([^ ]*\).*/\1/p')
    gres=$(printf '%s\n' "$detail" | sed -n 's/.*Gres=\([^ ]*\).*/\1/p')
    version=$(printf '%s\n' "$detail" | sed -n 's/.*Version=\([^ ]*\).*/\1/p')
    cpus=$(printf '%s\n' "$detail" | sed -n 's/.*CPUTot=\([0-9]*\).*/\1/p')
    alloc_cpus=$(printf '%s\n' "$detail" | sed -n 's/.*CPUAlloc=\([0-9]*\).*/\1/p')
    load=$(printf '%s\n' "$detail" | sed -n 's/.*CPULoad=\([^ ]*\).*/\1/p')
    alloc_gpus=$(printf '%s\n' "$detail" | sed -n 's/.*AllocTRES=.*gres\/gpu=\([0-9]*\).*/\1/p')
    alloc_gpus=${alloc_gpus:-0}
    tcp='Unavailable'
    timeout 5 bash -c "</dev/tcp/$node/22" >/dev/null 2>&1 && tcp='Reachable'
    probe='FAIL'
    timeout 40 srun --nodelist="$node" --ntasks=1 --cpus-per-task=1 --gres=gpu:0 --time=30 hostname >/dev/null 2>&1 && probe='PASS'
    health='Healthy'
    case "$state" in
        *DOWN*) health='DOWN' ;; *DRAIN*) health='DRAIN' ;; *NOT_RESPONDING*) health='NOT_RESPONDING' ;; esac
    result='Live'
    [ "$health" != 'Healthy' ] && result="$health"
    [ "$probe" != 'PASS' ] && result="$probe"
    [ "$tcp" != 'Reachable' ] && result='FAIL'
    python3 - "$node" "$state" "$health" "$version" "$tcp" "$load" "$alloc_cpus" "$cpus" "$alloc_gpus" "$gres" "$probe" "$result" <<'PY'
import json, sys
keys = ['node','slurm_state','health_state','slurm_daemon','tcp22','cpu_load','allocated_cpus','total_cpus','allocated_gpus','gpu_resources','probe','result']
print(json.dumps(dict(zip(keys, sys.argv[1:])), separators=(',', ':')))
PY
done

squeue -h -o '%i|%u|%j|%t|%C|%b|%N' 2>/dev/null | while IFS='|' read -r id user name state cpus tres node; do
    [ -n "$node" ] || continue
    is_worker "$node" || continue
    gpu=0
    if [[ "$tres" =~ gpu(:[^,]+)?:([0-9]+) ]]; then gpu="${BASH_REMATCH[2]}"; fi
    if [[ "$tres" =~ gpu:([0-9]+) ]]; then gpu="${BASH_REMATCH[1]}"; fi
    python3 - "$id" "$user" "$name" "$state" "$node" "$gpu" "$cpus" <<'PY'
import json, sys
keys = ['job_id','user','job_name','state','node','gpu_request','cpus']
print(json.dumps(dict(zip(keys, sys.argv[1:])), separators=(',', ':')))
PY
done
