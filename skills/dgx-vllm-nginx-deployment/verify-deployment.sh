#!/usr/bin/env bash
set -euo pipefail

: "${LB_URL:?Set LB_URL, including scheme and port}"
: "${VISION_FIXTURE:?Set VISION_FIXTURE to the local fixture path}"

DIRECT_URL="${DIRECT_URL:-}"
MODEL="${MODEL:-ensemble}"

check_models() {
    local label="$1" url="$2"
    printf '== %s: /v1/models ==\n' "$label"
    curl -skS -f --max-time 20 "$url/v1/models"
    printf '\n'
}

check_models nginx "$LB_URL"
if [[ -n "$DIRECT_URL" ]]; then
    check_models direct "$DIRECT_URL"
fi

printf '== nginx: chat ==\n'
curl -skS -f --max-time 120 \
    -H 'Content-Type: application/json' \
    -d '{"model":"'"$MODEL"'","messages":[{"role":"user","content":"What is 9 * 9? Reply with only the number."}],"max_tokens":96}' \
    "$LB_URL/v1/chat/completions"
printf '\n'

printf '== nginx: streaming ==\n'
curl -skS -f -N --max-time 120 \
    -H 'Content-Type: application/json' \
    -d '{"model":"'"$MODEL"'","messages":[{"role":"user","content":"Count from 1 to 3."}],"stream":true,"max_tokens":64}' \
    "$LB_URL/v1/chat/completions" | head -c 1600
printf '\n'

if command -v python3 >/dev/null 2>&1; then
    printf '== nginx: vision data URI ==\n'
    VISION_JSON="$(python3 - "$VISION_FIXTURE" "$MODEL" <<'PY'
import base64, json, sys
with open(sys.argv[1], "rb") as image:
    data = base64.b64encode(image.read()).decode()
print(json.dumps({
    "model": sys.argv[2],
    "messages": [{"role": "user", "content": [
        {"type": "text", "text": "Describe this image briefly."},
        {"type": "image_url", "image_url": {"url": "data:image/jpeg;base64," + data}},
    ]}],
    "max_tokens": 128,
}))
PY
)"
    curl -skS -f --max-time 180 -H 'Content-Type: application/json' \
        -d "$VISION_JSON" "$LB_URL/v1/chat/completions"
    printf '\n'
fi
