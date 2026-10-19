# serve/urerank — Reranking Endpoint

> Cross-encoder reranking endpoint: query + documents → relevance scores for RAG pipelines.

## Responsibility

- **Pairwise scoring** — (query, document) → relevance score [0, 1]
- **Batch reranking** — Single query × multiple documents efficiently
- **Model selection** — Multiple reranker models (BGE, Jina, Cohere-style, custom)
- **Score calibration** — Temperature scaling, sigmoid, min-max normalization
- **Truncation handling** — Long document chunking with aggregation
- **Structured output** — Scores, ranks, optional explanations

## Non-Responsibility

- **Authentication** → `uauth`
- **Rate limiting** → `ugate`
- **Inference execution** → `uai` → `ai/uinfer`
- **Audit logging** → `uaudit`
- **Protocol framing** → `uhttp`
- **Vector search** → `uembedding` + vector DB (this is post-retrieval)

## API

### Rerank (Cohere Compatible)

```http
POST /api/rerank/v1/rerank
Content-Type: application/json
Authorization: Bearer <token>

{
  "model": "bge-reranker-v2-m3",
  "query": "What is the capital of France?",
  "documents": [
    "Paris is the capital and most populous city of France.",
    "France is a country in Western Europe.",
    "The Eiffel Tower is located in Paris, France.",
    "Berlin is the capital of Germany."
  ],
  "top_n": 3,
  "return_documents": true,
  "max_chunks_per_doc": 10,
  "truncation": "auto"
}
```

```json
{
  "id": "rerank_01h8j9k2m3n4p5q6r7s8t9v0w1",
  "model": "bge-reranker-v2-m3",
  "results": [
    {
      "index": 0,
      "relevance_score": 0.9876,
      "document": { "text": "Paris is the capital and most populous city of France." }
    },
    {
      "index": 2,
      "relevance_score": 0.8234,
      "document": { "text": "The Eiffel Tower is located in Paris, France." }
    },
    {
      "index": 1,
      "relevance_score": 0.1234,
      "document": { "text": "France is a country in Western Europe." }
    }
  ],
  "meta": {
    "tokens_used": 156,
    "processing_time_ms": 42
  }
}
```

### Batch Rerank (Multiple Queries)

```http
POST /api/rerank/v1/rerank/batch
{
  "model": "bge-reranker-v2-m3",
  "queries": [
    "capital of France",
    "tallest building in Paris"
  ],
  "documents": [
    "Paris is the capital of France.",
    "Eiffel Tower is 330m tall.",
    "France is in Europe."
  ],
  "top_n": 2
}
```

```json
{
  "results": [
    {
      "query_index": 0,
      "results": [
        {"index": 0, "relevance_score": 0.99, "document": {"text": "Paris is the capital of France."}},
        {"index": 2, "relevance_score": 0.15, "document": {"text": "France is in Europe."}}
      ]
    },
    {
      "query_index": 1,
      "results": [
        {"index": 1, "relevance_score": 0.95, "document": {"text": "Eiffel Tower is 330m tall."}},
        {"index": 0, "relevance_score": 0.20, "document": {"text": "Paris is the capital of France."}}
      ]
    }
  ]
}
```

## Models

| Model ID | Family | Architecture | Max Seq | Languages | Notes |
|----------|--------|--------------|---------|-----------|-------|
| `bge-reranker-v2-m3` | BGE | Cross-encoder (XLM-RoBERTa) | 8192 | 100+ | Multilingual, long context |
| `bge-reranker-base` | BGE | Cross-encoder (BERT-base) | 512 | EN | Fast, general |
| `bge-reranker-large` | BGE | Cross-encoder (BERT-large) | 512 | EN | Higher quality |
| `jina-reranker-v2-base` | Jina | Cross-encoder (JinaBERT) | 8192 | 100+ | Flash attention |
| `jina-reranker-v2-base-multilingual` | Jina | Cross-encoder | 8192 | 100+ | Multilingual |
| `ms-marco-minilm-l6-v2` | MS-MARCO | Cross-encoder (MiniLM) | 512 | EN | Lightweight |
| `ms-marco-minilm-l12-v2` | MS-MARCO | Cross-encoder (MiniLM) | 512 | EN | Balanced |
| `cohere-rerank-v3.5` | Cohere | Proprietary | 4096 | 100+ | Commercial API compatible |
| `custom-*` | Custom | Configurable | Configurable | Configurable | Domain-specific |

## Long Document Handling

```rust
pub enum TruncationStrategy {
    Auto,                          // Chunk + aggregate (default)
    FirstN { tokens: usize },      // First N tokens only
    LastN { tokens: usize },       // Last N tokens only
    SlidingWindow {                // Overlapping chunks
        chunk_size: usize,
        overlap: usize,
        aggregation: Aggregation,  // Max | Mean | WeightedMean
    },
    None,                          // Fail if too long
}

pub enum Aggregation {
    Max,                           // Max score across chunks (default)
    Mean,                          // Average
    WeightedMean {                 // Position-weighted
        decay: f32,                // 0.9 = exponential decay
    },
    Learned,                       // Small neural aggregator
}
```

- **Default**: Sliding window (512 tokens, 128 overlap) → max aggregation
- **Chunk-level scores**: Returned if `return_chunks: true`

## Score Calibration

```rust
pub struct CalibrationConfig {
    pub enabled: bool,
    pub method: CalibrationMethod,    // TemperatureScaling | Sigmoid | MinMax | Isotonic
    pub temperature: f32,             // For TemperatureScaling (default: 1.0)
    pub min_score: f32,               // For MinMax (default: 0.0)
    pub max_score: f32,               // For MinMax (default: 1.0)
}

pub enum CalibrationMethod {
    TemperatureScaling,               // score = sigmoid(logit / T)
    Sigmoid,                          // score = sigmoid(logit)
    MinMax,                           // Linear stretch to [min, max]
    IsotonicRegression,               // Non-parametric (requires calibration set)
    None,                             // Raw logits
}
```

- **Calibration data**: Collected from user feedback (clicks, dwell time, explicit ratings)
- **Periodic retraining**: Daily/weekly calibration model update

## Configuration

```toml
[urerank]
# Models
models = [
  { id = "bge-reranker-v2-m3", family = "bge", max_seq = 8192, batch_size = 32 },
  { id = "bge-reranker-base", family = "bge", max_seq = 512, batch_size = 64 },
  { id = "jina-reranker-v2-base", family = "jina", max_seq = 8192, batch_size = 32 },
  { id = "ms-marco-minilm-l6-v2", family = "msmarco", max_seq = 512, batch_size = 128 },
]

# Defaults
defaults = {
  model = "bge-reranker-v2-m3"
  top_n = 10
  return_documents = false
  max_chunks_per_doc = 10
  truncation = "auto"
}

# Long document handling
truncation = {
  strategy = "sliding_window"
  chunk_size = 512
  overlap = 128
  aggregation = "max"
}

# Score calibration
calibration = {
  enabled = true
  method = "temperature_scaling"
  temperature = 1.0
  auto_update = true
  update_interval = "1d"
}

# Batching
batching = {
  max_batch_pairs = 256  // query × doc pairs per batch
  max_query_length = 512
  max_doc_length = 8192
  timeout = "10s"
}

# Caching
cache = {
  enabled = true
  ttl = "1h"
  max_entries = 100000
  key_prefix = "rr:"
}
```

## Integration

- **Upstream**: `ugate` (routes `/api/rerank/*` here), `uauth` (identity)
- **Downstream**: `uai` (rerank inference), `uaudit` (usage)
- **External**: RAG pipelines (LangChain, LlamaIndex, custom), vector databases

## RAG Pipeline Position

```
User Query
    │
    ▼
[Embedding] → Vector Search → Top-K Documents (e.g., 50)
    │                                    │
    └──────────────┬─────────────────────┘
                   ▼
          [Reranker] → Top-N Re-ranked (e.g., 5)
                   │
                   ▼
          [LLM] → Final Answer (with citations)
```

## Metrics

| Metric | Type | Labels |
|--------|------|--------|
| `urerank_requests_total` | Counter | `model`, `batch`, `status` |
| `urerank_pairs_processed_total` | Counter | `model` |
| `urerank_latency_seconds` | Histogram | `model`, `num_docs` |
| `urerank_throughput_pairs_per_sec` | Gauge | `model` |
| `urerank_score_distribution` | Histogram | `model` (score buckets) |
| `urerank_calibration_temperature` | Gauge | `model` |

## Status

🔴 **Planned** — API defined, `uai` integration pending.