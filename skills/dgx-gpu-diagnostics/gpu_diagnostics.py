#!/usr/bin/env python3
"""Run the fixed single-GPU CUDA health workload."""

import json
import os
import sys

import torch


def emit(payload: dict, exit_code: int) -> None:
    print(json.dumps(payload, separators=(",", ":")), flush=True)
    raise SystemExit(exit_code)


uuid = os.environ.get("CUDA_VISIBLE_DEVICES")
if not uuid:
    print("CUDA_VISIBLE_DEVICES is required", file=sys.stderr)
    raise SystemExit(2)

try:
    torch.cuda.init()
    model = torch.cuda.get_device_name(0)
    ballast = [
        torch.empty(1024 * 1024 * 1024 // 4, dtype=torch.float32, device="cuda")
        for _ in range(50)
    ]
    x = torch.randn(8192, 4096, device="cuda", dtype=torch.float32)
    w = torch.randn(256, 4096, device="cuda", dtype=torch.float32)
    for _ in range(500):
        torch.nn.functional.linear(x, w)
        torch.cuda.synchronize()
except torch.cuda.OutOfMemoryError as error:
    emit({"result": "FAIL", "uuid": uuid, "model": model if "model" in locals() else None, "error_type": type(error).__name__, "error": str(error).splitlines()[0]}, 1)
except RuntimeError as error:
    message = str(error)
    gpu_markers = ("CUDA", "cuda", "CUBLAS", "device-side assert", "NVIDIA")
    if not any(marker in message for marker in gpu_markers):
        raise
    emit({"result": "FAIL", "uuid": uuid, "model": model if "model" in locals() else None, "error_type": type(error).__name__, "error": message.splitlines()[0]}, 1)
else:
    emit({"result": "PASS", "uuid": uuid, "model": model}, 0)
