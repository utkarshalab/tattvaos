# serve/uai — AI Inference Serving Adapter

> Domain adapter for serving AI inference workloads: LLM, embeddings, reranking, multimodal with KV cache, batching, and model routing.

## Responsibility

- **Model routing** — Select model + worker based on request, capability, affinity
- **KV cache management** — Prefix caching, cross-request reuse, eviction policies
- **Continuous batching** — Dynamic batch formation, prefill/decode separation
- **Streaming tokens** — SSE token-by-token, completion tokens, usage metadata
- **Multi-LoRA** — Dynamic adapter loading, per-request LoRA selection
- **Multimodal** — Image/audio/video input, tokenization, preprocessing
- **Speculative decoding** — Draft model + verification, acceptance rate tracking

## Non-Responsibility

- **Authentication** → `uauth`
- **Firewall** → `niti`
- **Load balancing** → `ulb` (selects inference worker node)
- **Audit logging** → `uaudit`
- **Protocol framing** → `uhttp`/`uws`/`ustream`
- **Model execution** → `ai/uinfer` (the actual inference engine)

## Architecture

```
Request (ugate → userve)
         │
         ▼
┌─────────────────────────────────────────────────────────────┐
│ uai Adapter                                                 │
├─────────────────────────────────────────────────────────────┤
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │ Request      │  │ Model        │  │ KV Cache     │       │
│  │ Router       │──▶│ Selector     │──▶│ Manager      │       │
│  │ (params →    │   │ (model,      │   │ (prefix      │       │
│  │  model, lora)│   │  quant, lora)│   │  match,      │       │
│  └──────────────┘   └──────────────┘   │  eviction)   │       │
│         │                │             └──────────────┘       │
│         ▼                ▼                  │                  │
│  ┌─────────────────────────────────────────┴──────────────┐   │
│  │              Batching Engine                            │   │
│  │  Continuous Batching | Prefill Chunking | Speculative  │   │
│  └─────────────────────────┬───────────────────────────────┘   │
│                            │                                     │
│                            ▼                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              uinfer Client (gRPC/Unix)                  │   │
│  │  BatchRequest → Stream<BatchResponse>                   │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## Request Routing

```rust
pub struct InferenceRequest {
    pub model: ModelSelector,             // Exact | Family | Capability | Auto
    pub messages: Vec<Message>,           // Chat format
    pub prompt: Option<String>,           // Completion format (legacy)
    pub parameters: InferenceParams,
    pub lora: Option<LoraSelector>,       // None | Specific | Auto
    pub stream: bool,                     // SSE streaming
    pub priority: Priority,               // Normal | High | Background
    pub affinity: Option<AffinityKey>,    // Session stickiness
}

pub enum ModelSelector {
    Exact(String),                        // "llama-3-70b-instruct-q4"
    Family(String),                       // "llama-3" (latest instruct)
    Capability(CapabilityQuery),          // { min_context: 128k, modality: ["text", "vision"] }
    Auto,                                 // Route based on load, cost, latency
}
```

## KV Cache Management

```rust
pub struct KvCacheConfig {
    pub max_size_gb: u64,                 // Total cache budget
    pub block_size: usize,                // 256 tokens per block
    pub prefix_match_min: usize,          // Min prefix tokens to reuse (default: 128)
    pub eviction: EvictionPolicy,         // LRU | LFU | TTL | Hybrid
    pub ttl: Duration,                    // Max age (default: 1h)
    pub reserve_for_prefill: f32,         // Fraction reserved for prefill (0.3)
}

pub enum EvictionPolicy {
    Lru,
    Lfu,
    Ttl { ttl: Duration },
    Hybrid { lru_weight: 0.7, lfu_weight: 0.3 },
}
```

- **Prefix caching**: Hash first N tokens → cache key; reuse on exact match
- **Cross-request**: Share cache across requests with same prefix (system prompt, few-shot)
- **Multi-model**: Separate cache per model; shared prefix across quantizations
- **Eviction**: Background compaction; prioritize active sessions

## Continuous Batching

```
Time ────────────────────────────────────────────────────────────▶

Request A: [Prefill ──────][Decode ────────────────────────────]
Request B:          [Prefill ────][Decode ──────────────────────]
Request C:                 [Prefill ──][Decode ─────────────────]
Request D:                        [Prefill ──][Decode ──────────]

Batch 1:     ████████████████  (A prefill)
Batch 2:     ████████████████  (A decode + B prefill)
Batch 3:     ████████████████  (A decode + B decode + C prefill)
Batch 4:     ████████████████  (A decode + B decode + C decode + D prefill)
Batch 5:     ████████████████  (B decode + C decode + D decode)
...
```

- **Dynamic batching**: New requests join at next decode step
- **Prefill chunking**: Large prefill split across batches
- **Priority preemption**: High-priority requests can preempt batch
- **Padding**: Right-pad to max sequence in batch; masked attention

## Speculative Decoding

```
Draft Model (small, fast)          Target Model (large, accurate)
         │                                 │
         ▼                                 │
   Generate k tokens ──────────────▶ Verify k tokens
         │                                 │
         │    Accept first m tokens        │
         │    (m ≤ k, based on prob)       │
         ▼                                 ▼
   Next draft from accepted            Next draft from accepted
```

```rust
pub struct SpeculativeConfig {
    pub enabled: bool,
    pub draft_model: String,              // "llama-3-8b-draft"
    pub num_draft_tokens: u32,            // 4-8 typical
    pub acceptance_threshold: f32,        // 0.9 (probability)
    pub max_mismatch: u32,                // Reset on > N mismatches
    pub verification_batch: bool,         // Batch verify multiple requests
}
```

## Multi-LoRA

```rust
pub struct LoraConfig {
    pub max_loras_per_batch: u32,         // 8-32 (hardware dependent)
    pub lora_dir: PathBuf,                // /models/loras/
    pub lazy_load: bool,                  // Load on first use
    pub memory_budget_gb: u32,            // Adapter weight budget
}
```

- **Batch LoRA**: Group requests by LoRA; pad with identity (no-op) for others
- **S-LoRA**: Unified paging for LoRA weights (if supported by `uinfer`)

## Multimodal Pipeline

```
Image Input → Preprocess (resize, normalize) → Vision Encoder → Image Tokens
Audio Input → Preprocess (resample, mel)     → Audio Encoder  → Audio Tokens
Video Input → Sample frames                  → Vision Encoder → Video Tokens
                                                                    │
                                                                    ▼
                                                        Concat with Text Tokens
                                                                    │
                                                                    ▼
                                                          LLM Forward Pass
```

## Streaming Response (SSE)

```rust
// data: {"id":"cmpl_123","object":"chat.completion.chunk","choices":[{"delta":{"content":"Hello"},"index":0}]}
// data: {"id":"cmpl_123","object":"chat.completion.chunk","choices":[{"delta":{"content":" world"},"index":0}]}
// data: {"id":"cmpl_123","object":"chat.completion.chunk","choices":[{"delta":{},"index":0,"finish_reason":"stop"}]}
// data: [DONE]
```

- **First token latency**: Target < 200ms (prefill + first decode)
- **Token throughput**: Track tokens/sec for billing/metrics
- **Usage**: Include `prompt_tokens`, `completion_tokens`, `total_tokens` in final chunk

## Configuration

```toml
[uai]
# Model registry (synced from ai/uinfer)
models = [
  { id = "llama-3-70b-instruct", family = "llama-3", quantization = "q4_k_m", context = 131072, modality = ["text"], loras = ["coding", "reasoning", "sql"] },
  { id = "llama-3-8b-instruct", family = "llama-3", quantization = "q4_k_m", context = 131072, modality = ["text"] },
  { id = "llama-3-70b-vision", family = "llama-3", quantization = "q4_k_m", context = 131072, modality = ["text", "vision"] },
  { id = "embed-v3", family = "bge", quantization = "fp16", context = 8192, modality = ["text"], task = "embedding" },
  { id = "rerank-v2", family = "bge", quantization = "fp16", context = 512, modality = ["text"], task = "rerank" },
]

# Routing
routing = {
  default_model = "llama-3-8b-instruct"
  auto_select = true
  prefer_local = true
  cost_aware = true
}

# KV Cache
kv_cache = {
  max_size_gb = 32
  block_size = 256
  prefix_match_min = 128
  eviction = "hybrid"
  ttl = "1h"
  reserve_for_prefill = 0.3
}

# Batching
batching = {
  max_batch_size = 256
  max_prefill_tokens = 4096
  max_decode_tokens = 4096
  prefill_chunk_size = 512
  priority_levels = 3
}

# Speculative Decoding
speculative = {
  enabled = true
  draft_model = "llama-3-8b-draft"
  num_draft_tokens = 5
  acceptance_threshold = 0.9
}

# LoRA
lora = {
  max_per_batch = 16
  lazy_load = true
  memory_budget_gb = 4
}

# Streaming
streaming = {
  sse_format = "openai"  # openai | anthropic | raw
  include_usage = true
  include_logprobs = false
  first_token_timeout = "10s"
  token_timeout = "5s"
}

# uinfer connection
uinfer = {
  endpoint = "unix:///run/tattva/uinfer.sock"
  max_concurrent_batches = 32
  request_timeout = "60s"
}
```

## Integration

- **Upstream**: `ugate` (routes `/api/ai/*` here), `ulb` (selects inference worker)
- **Downstream**: `ai/uinfer` (gRPC/Unix: `BatchRequest`/`BatchResponse` stream)
- **External**: Model registry (from `ai/uinfer`), LoRA store, KV cache storage (Redis/etcd for distributed)

## Metrics

| Metric | Type | Labels |
|--------|------|--------|
| `uai_requests_total` | Counter | `model`, `streaming`, `status` |
| `uai_prefill_latency_seconds` | Histogram | `model`, `batch_size` |
| `uai_decode_latency_seconds` | Histogram | `model`, `batch_size` |
| `uai_tokens_per_second` | Gauge | `model` |
| `uai_kv_cache_hit_rate` | Gauge | `model` |
| `uai_kv_cache_usage_bytes` | Gauge | `model` |
| `uai_batch_size` | Histogram | `model`, `phase` (prefill/decode) |
| `uai_speculative_acceptance_rate` | Gauge | `model` |
| `uai_lora_loads_total` | Counter | `lora_id` |

## OpenAI Compatibility (`uopenai`)

The `uopenai` project provides a thin translation layer on top of `uai`:
- `/v1/chat/completions` → `uai` chat format
- `/v1/completions` → `uai` completion format
- `/v1/embeddings` → `uai` embedding model
- `/v1/rerank` → `uai` rerank model

## Status

🔴 **Planned** — Interface defined, `uinfer` integration pending.