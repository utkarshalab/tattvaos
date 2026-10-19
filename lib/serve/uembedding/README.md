# serve/uembedding — Embedding Endpoint

> Specialized endpoint for vector embedding generation: text → dense vectors, batch encoding, normalization, Matryoshka dimensions.

## Responsibility

- **Text encoding** — Single/batch text → dense vector embeddings
- **Model selection** — Multiple embedding models (BGE, E5, GTE, custom)
- **Batch processing** — Efficient batching with dynamic padding
- **Normalization** — L2 normalization, optional
- **Dimension truncation** — Matryoshka: 384, 768, 1024, 1536, 3072 from single model
- **Pooling strategies** — CLS, mean, max, last-token, weighted
- **Quantization** — FP32, FP16, INT8, binary output formats

## Non-Responsibility

- **Authentication** → `uauth`
- **Rate limiting** → `ugate`
- **Inference execution** → `uai` → `ai/uinfer`
- **Audit logging** → `uaudit`
- **Protocol framing** → `uhttp`/`ustream`

## API

### Single Embedding (OpenAI Compatible)

```http
POST /api/embedding/v1/embeddings
Content-Type: application/json
Authorization: Bearer <token>

{
  "model": "bge-large-en-v1.5",
  "input": "Hello world",
  "encoding_format": "float",
  "dimensions": 1024,
  "normalize": true
}
```

```json
{
  "object": "list",
  "data": [
    {
      "object": "embedding",
      "index": 0,
      "embedding": [0.0123, -0.0456, ...],  // 1024 floats
      "tokens_used": 2
    }
  ],
  "model": "bge-large-en-v1.5",
  "usage": {
    "prompt_tokens": 2,
    "total_tokens": 2
  }
}
```

### Batch Embedding

```http
POST /api/embedding/v1/embeddings
{
  "model": "bge-large-en-v1.5",
  "input": ["Text 1", "Text 2", "Text 3", "..."],
  "encoding_format": "float",
  "dimensions": 768,
  "normalize": true,
  "batch_size": 32  // Optional: override auto-batching
}
```

```json
{
  "object": "list",
  "data": [
    {"object": "embedding", "index": 0, "embedding": [...], "tokens_used": 5},
    {"object": "embedding", "index": 1, "embedding": [...], "tokens_used": 3},
    {"object": "embedding", "index": 2, "embedding": [...], "tokens_used": 7}
  ],
  "model": "bge-large-en-v1.5",
  "usage": {"prompt_tokens": 15, "total_tokens": 15}
}
```

### Async Batch (Large Datasets)

```http
POST /api/embedding/v1/embeddings/batch
{
  "model": "bge-large-en-v1.5",
  "input_uri": "s3://bucket/input.jsonl",  // {"text": "..."} per line
  "output_uri": "s3://bucket/output/",
  "encoding_format": "float",
  "dimensions": 1024,
  "normalize": true,
  "notify_webhook": "https://app.example.com/embedding-complete"
}
```

```json
{
  "batch_id": "batch_01h8j9k2m3n4p5q6r7s8t9v0w1",
  "status": "accepted",
  "estimated_completion": "2026-10-12T14:45:00Z"
}
```

## Models

| Model ID | Family | Dimensions (Native) | Matryoshka | Max Seq | Pooling | Use Case |
|----------|--------|---------------------|------------|---------|---------|----------|
| `bge-large-en-v1.5` | BGE | 1024 | 256-1024 | 512 | CLS | General EN |
| `bge-base-en-v1.5` | BGE | 768 | 256-768 | 512 | CLS | Fast EN |
| `bge-small-en-v1.5` | BGE | 384 | 128-384 | 512 | CLS | Tiny EN |
| `bge-m3` | BGE | 1024 | 256-1024 | 8192 | CLS | Multilingual |
| `e5-large-v2` | E5 | 1024 | 256-1024 | 512 | Mean | General |
| `e5-base-v2` | E5 | 768 | 256-768 | 512 | Mean | Fast |
| `gte-large-en-v1.5` | GTE | 1024 | 256-1024 | 512 | CLS | Retrieval |
| `gte-base-en-v1.5` | GTE | 768 | 256-768 | 512 | CLS | Fast retrieval |
| `instructor-xl` | INSTRUCTOR | 768 | - | 512 | CLS | Instruction-tuned |
| `custom-*` | Custom | Configurable | Configurable | Configurable | Configurable | Domain-specific |

## Pooling Strategies

```rust
pub enum PoolingStrategy {
    Cls,                           // [CLS] token (BERT-style)
    Mean,                          // Mean of all tokens (E5-style)
    Max,                           // Max over tokens
    LastToken,                     // Last non-padding token (GPT-style)
    WeightedMean {                 // Attention-weighted
        attention_layer: usize,
        attention_head: usize,
    },
    Custom(String),                // Plugin
}
```

## Matryoshka Dimension Truncation

```rust
// Single model (1024-dim) → Multiple output dimensions
// No quality loss for truncated dimensions (trained with Matryoshka loss)

pub struct MatryoshkaConfig {
    pub enabled: bool,
    pub supported_dims: Vec<usize>,   // [256, 384, 512, 768, 1024]
    pub default_dim: usize,           // 1024
    pub truncate_method: TruncateMethod,  // Slice | LearnedProjection
}
```

## Output Formats

| Format | Description | Use Case |
|--------|-------------|----------|
| `float` | FP32 array (default) | General purpose |
| `float16` | FP16 array (base64) | Bandwidth-constrained |
| `int8` | INT8 quantized (base64) | Storage-constrained |
| `binary` | Packed bits (base64) | Binary similarity (Hamming) |
| `ubinary` | Unpacked binary (0/1 array) | Debugging |

## Configuration

```toml
[uembedding]
# Models
models = [
  { id = "bge-large-en-v1.5", family = "bge", dims = 1024, matryoshka = [256, 384, 512, 768, 1024], max_seq = 512, pooling = "cls" },
  { id = "bge-base-en-v1.5", family = "bge", dims = 768, matryoshka = [256, 384, 512, 768], max_seq = 512, pooling = "cls" },
  { id = "bge-m3", family = "bge", dims = 1024, matryoshka = [256, 384, 512, 768, 1024], max_seq = 8192, pooling = "cls" },
  { id = "e5-large-v2", family = "e5", dims = 1024, matryoshka = [256, 384, 512, 768, 1024], max_seq = 512, pooling = "mean" },
  { id = "gte-large-en-v1.5", family = "gte", dims = 1024, matryoshka = [256, 384, 512, 768, 1024], max_seq = 512, pooling = "cls" },
]

# Defaults
defaults = {
  model = "bge-large-en-v1.5"
  encoding_format = "float"
  normalize = true
  dimensions = 1024
}

# Batching
batching = {
  max_batch_size = 256
  max_sequence_length = 8192
  dynamic_padding = true
  timeout = "30s"
}

# Async batch
async_batch = {
  enabled = true
  max_input_size = "1GB"
  max_output_size = "10GB"
  worker_pool = "embedding-workers"
  checkpoint_interval = "1000"
}

# Output
output = {
  float_precision = 6  # Decimal places for JSON
  base64_encoding = "standard"  # standard | url_safe
}

# Caching
cache = {
  enabled = true
  ttl = "24h"
  max_entries = 1000000
  key_prefix = "emb:"
}
```

## Integration

- **Upstream**: `ugate` (routes `/api/embedding/*` here), `uauth` (identity)
- **Downstream**: `uai` (embedding inference), `uaudit` (usage)
- **External**: Vector databases (Qdrant, Pinecone, Weaviate, Milvus), RAG pipelines

## Metrics

| Metric | Type | Labels |
|--------|------|--------|
| `uembedding_requests_total` | Counter | `model`, `batch`, `status` |
| `uembedding_tokens_total` | Counter | `model` |
| `uembedding_latency_seconds` | Histogram | `model`, `batch_size` |
| `uembedding_batch_throughput` | Gauge | `model` (vectors/sec) |
| `uembedding_cache_hit_rate` | Gauge | `model` |
| `uembedding_async_batches_active` | Gauge | |

## Status

🔴 **Planned** — API defined, `uai` integration pending.