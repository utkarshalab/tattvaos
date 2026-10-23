# ai/uinfer — Inference Engine

> The core inference engine. The heart of Utkarsha OS.

Orchestrates the full inference pipeline: tokenize → prefill → decode → detokenize.
Calls into `ai/kernels` for compute. Manages `ai/memory` for KV cache.

Part of the `ai/` category in Utkarsha OS.
