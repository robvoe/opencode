#!/usr/bin/env python3
"""Blindfolded offline smoke-test for a Roboflow inference-server model cache.

Loads a model and runs one object-detection inference against a local
Roboflow inference server (http://127.0.0.1:<port>). Intended to be run
against a container that has all Roboflow hosts blackholed, with the
prepared model cache mounted at the production MODEL_CACHE_DIR path.

Expected usage (run with the active python env that has inference_sdk; key from env/.env, never inline):
    VIRTUAL_ENV or conda/pdm/uv env with inference_sdk
    python smoke_test.py \
        --url http://localhost:9001 \
        --api-key "$ROBOFLOW_API_KEY" \
        --model-id <model>/<version> \
        --image path/to/test.jpg

Exits non-zero on failure so it can gate a deploy. Prints a short summary
(load status, detections). Network attempts are verified separately by
grepping the container logs (the test itself cannot see that).
"""
import argparse
import json
import sys
import time

def main() -> int:
    parser = argparse.ArgumentParser(description="Offline RF model smoke test")
    parser.add_argument("--url", default="http://localhost:9001")
    parser.add_argument("--api-key", required=True)
    parser.add_argument("--model-id", required=True, help="e.g. prospekt-produkt-erkennung/3")
    parser.add_argument("--image", required=True, help="path to a JPEG/PNG test image")
    args = parser.parse_args()

    try:
        from inference_sdk import InferenceHTTPClient
    except ImportError:
        print("inference_sdk not installed - cannot run; install it (pdm/pip) or use curl.", file=sys.stderr)
        return 2

    client = InferenceHTTPClient(api_url=args.url, api_key=args.api_key)

    t0 = time.time()
    try:
        loaded = client.load_model(model_id=args.model_id)
        print(f"load_model -> {loaded}")
    except Exception as e:  # noqa: BLE001
        print(f"load_model FAILED: {e!r}", file=sys.stderr)
        return 1

    try:
        result = client.infer(args.image, model_id=args.model_id)
        dt = time.time() - t0
    except Exception as e:  # noqa: BLE001
        print(f"infer FAILED: {e!r}", file=sys.stderr)
        return 1

    preds = result.get("predictions", [])
    print(f"infer ok in {dt*1000:.0f} ms, {len(preds)} detections")
    for p in preds[:5]:
        print(f"    {p.get('class')} conf={p.get('confidence'):.3f} "
              f"bbox=({p.get('x'):.0f},{p.get('y'):.0f},{p.get('width'):.0f}x{p.get('height'):.0f})")

    print("\nREMINDER: confirm zero network attempts in the container logs:")
    print("    grep -cE 'get_one_page_of_model_metadata|RetryError|Connectivity error' <(docker logs rf-smoke)")
    return 0

if __name__ == "__main__":
    sys.exit(main())
