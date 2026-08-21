# Qwen3.8 validated profile

This profile is an opt-in starting point, not an automatic deployment decision.
Confirm every value before use.

```text
Model: orcarouter/Qwen3.8-27B-Uncensored-FP8
Validated image: dpo-harbor.infra.server.lan#/dgx-mirror/vllm/vllm-openai:v0.24.0
Topology: one TP=1 replica per GPU
Context: 262144
KV cache: fp8
Max sequences: 16
Speculation: {"method":"mtp","num_speculative_tokens":3}
Reasoning parser: qwen3
Tool parser: qwen3_coder
Served name: ensemble
TLS behind nginx: disabled in vLLM
```

The known cache path was worker-local and must be revalidated each run. Do not
copy this profile's certificate paths or port numbers into a new deployment.
