# serve/uopenai — OpenAI-Compatible API Layer

> Thin translation layer exposing OpenAI-compatible REST API on top of `uai` adapter.

## Responsibility

- **Request translation** — OpenAI format → `uai` internal format
- **Response translation** — `uai` streaming → OpenAI SSE format
- **Model mapping** — OpenAI model IDs → Tattva model registry
- **Parameter validation** — OpenAI-specific params, defaults, limits
- **Error mapping** — `uai` errors → OpenAI error codes
- **Usage tracking** — Token counting for billing compatibility

## Non-Responsibility

- **Authentication** → `uauth` (API key → identity with scopes)
- **Rate limiting** → `ugate` (per-identity, per-model)
- **Inference execution** → `uai` → `ai/uinfer`
- **Audit logging** → `uaudit`
- **Protocol framing** → `uhttp`/`ustream`

## Supported Endpoints

| OpenAI Endpoint | Tattva Route | `uai` Operation |
|-----------------|--------------|-----------------|
| `POST /v1/chat/completions` | `/api/ai/v1/chat/completions` | Chat completion (streaming) |
| `POST /v1/completions` | `/api/ai/v1/completions` | Text completion (legacy) |
| `POST /v1/embeddings` | `/api/ai/v1/embeddings` | Embedding generation |
| `POST /v1/rerank` | `/api/ai/v1/rerank` | Reranking (extension) |
| `GET /v1/models` | `/api/ai/v1/models` | List available models |
| `GET /v1/models/{id}` | `/api/ai/v1/models/{id}` | Model info |
| `POST /v1/moderations` | `/api/ai/v1/moderations` | Content moderation (extension) |
| `GET /v1/usage` | `/api/ai/v1/usage` | Usage statistics (extension) |

## Request Translation

### Chat Completions

```json
// OpenAI Request
{
  "model": "gpt-4",
  "messages": [
    {"role": "system", "content": "You are helpful."},
    {"role": "user", "content": "Hello!"}
  ],
  "temperature": 0.7,
  "max_tokens": 100,
  "stream": true,
  "top_p": 1.0,
  "frequency_penalty": 0.0,
  "presence_penalty": 0.0,
  "stop": ["\n\n"],
  "tools": [...],
  "tool_choice": "auto",
  "response_format": {"type": "json_object"},
  "user": "user_123"
}
```

```rust
// uai Internal Request
InferenceRequest {
    model: ModelSelector::Family("gpt-4-family"),  // Mapped
    messages: vec![
        Message { role: "system", content: "You are helpful." },
        Message { role: "user", content: "Hello!" }
    ],
    parameters: InferenceParams {
        temperature: 0.7,
        max_tokens: Some(100),
        top_p: 1.0,
        frequency_penalty: 0.0,
        presence_penalty: 0.0,
        stop_sequences: vec!["\n\n"],
        // tools → structured generation grammar
        // response_format → JSON schema constraint
    },
    stream: true,
    priority: Priority::Normal,
}
```

### Embeddings

```json
// OpenAI Request
{
  "model": "text-embedding-3-large",
  "input": ["Hello world", "Another text"],
  "encoding_format": "float",
  "dimensions": 1024,
  "user": "user_123"
}
```

```rust
// uai Internal Request
InferenceRequest {
    model: ModelSelector::Exact("embed-v3-large"),
    messages: [],  // Not used for embeddings
    parameters: InferenceParams {
        task: Task::Embedding,
        embedding_input: vec!["Hello world", "Another text"],
        encoding_format: "float",
        dimensions: Some(1024),  // Matryoshka / truncation
    },
    stream: false,
}
```

## Model Mapping

| OpenAI Model ID | Tattva Model Family | Notes |
|-----------------|---------------------|-------|
| `gpt-4`, `gpt-4-turbo` | `llama-3-70b-instruct` | Best available |
| `gpt-4o` | `llama-3-70b-instruct` | Alias |
| `gpt-3.5-turbo` | `llama-3-8b-instruct` | Fast/cheap |
| `text-embedding-3-large` | `embed-v3-large` | 3072 dim |
| `text-embedding-3-small` | `embed-v3-small` | 1536 dim |
| `text-embedding-ada-002` | `embed-v2` | 1536 dim (legacy) |

```toml
[uopenai.model_mapping]
"gpt-4" = "llama-3-70b-instruct"
"gpt-4-turbo" = "llama-3-70b-instruct"
"gpt-4o" = "llama-3-70b-instruct"
"gpt-3.5-turbo" = "llama-3-8b-instruct"
"text-embedding-3-large" = "embed-v3-large"
"text-embedding-3-small" = "embed-v3-small"
"text-embedding-ada-002" = "embed-v2"
```

## Streaming Response (SSE)

```rust
// OpenAI SSE Format (data: JSON\n\n)
data: {"id":"chatcmpl-123","object":"chat.completion.chunk","created":1699999999,"model":"gpt-4","choices":[{"index":0,"delta":{"role":"assistant","content":"Hello"},"finish_reason":null}]}

data: {"id":"chatcmpl-123","object":"chat.completion.chunk","created":1699999999,"model":"gpt-4","choices":[{"index":0,"delta":{"content":" world"},"finish_reason":null}]}

data: {"id":"chatcmpl-123","object":"chat.completion.chunk","created":1699999999,"model":"gpt-4","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}

data: [DONE]
```

- **First chunk**: Includes `role: "assistant"` in delta
- **Subsequent chunks**: Only `content` in delta
- **Final chunk**: `finish_reason: "stop" | "length" | "tool_calls" | "content_filter"`
- **Usage**: Included in final chunk if `stream_options: { "include_usage": true }`

## Error Mapping

| `uai` Error | OpenAI Error | HTTP Status |
|-------------|--------------|-------------|
| `ModelNotFound` | `model_not_found` | 404 |
| `InvalidParameter` | `invalid_request_error` | 400 |
| `ContextLengthExceeded` | `context_length_exceeded` | 400 |
| `RateLimited` | `rate_limit_exceeded` | 429 |
| `AuthenticationFailed` | `invalid_api_key` | 401 |
| `InsufficientQuota` | `insufficient_quota` | 403 |
| `InternalError` | `internal_error` | 500 |
| `Overloaded` | `service_unavailable` | 503 |

```json
{
  "error": {
    "message": "This model's maximum context length is 4096 tokens...",
    "type": "context_length_exceeded",
    "param": "messages",
    "code": "context_length_exceeded"
  }
}
```

## Tool/Function Calling

```json
// OpenAI Request with tools
{
  "tools": [
    {
      "type": "function",
      "function": {
        "name": "get_weather",
        "description": "Get current weather",
        "parameters": {
          "type": "object",
          "properties": {
            "location": {"type": "string"},
            "unit": {"type": "string", "enum": ["celsius", "fahrenheit"]}
          },
          "required": ["location"]
        }
      }
    }
  ],
  "tool_choice": "auto"
}
```

- **Translation**: Tools → JSON Schema grammar constraints in `uinfer`
- **Execution**: Tool calls returned in stream; client executes, sends results back
- **Parallel**: Multiple tool calls in single turn supported

## Configuration

```toml
[uopenai]
# Base path
base_path = "/v1"

# Model mapping (OpenAI ID -> Tattva model selector)
model_mapping = {
  "gpt-4" = "llama-3-70b-instruct"
  "gpt-4-turbo" = "llama-3-70b-instruct"
  "gpt-4o" = "llama-3-70b-instruct"
  "gpt-3.5-turbo" = "llama-3-8b-instruct"
  "text-embedding-3-large" = "embed-v3-large"
  "text-embedding-3-small" = "embed-v3-small"
  "text-embedding-ada-002" = "embed-v2"
}

# Defaults
defaults = {
  temperature = 0.7
  max_tokens = 4096
  top_p = 1.0
  stream = false
}

# Limits (per-request)
limits = {
  max_messages = 100
  max_message_length = "100KB"
  max_tools = 64
  max_tool_call_depth = 10
  max_context_tokens = 131072  # Enforced per-model
}

# Streaming
streaming = {
  sse_format = "openai"
  include_usage = true
  chunk_buffer_size = "4KB"
  flush_interval = "10ms"
}

# Error handling
errors = {
  include_stack_trace = false
  sanitize_messages = true
}
```

## Integration

- **Upstream**: `ugate` (routes `/v1/*` here), `uauth` (API key → identity)
- **Downstream**: `uai` (inference requests), `uaudit` (usage logging)
- **External**: OpenAI SDKs (Python, JS, Go, etc.) — drop-in compatible

## Metrics

| Metric | Type | Labels |
|--------|------|--------|
| `uopenai_requests_total` | Counter | `endpoint`, `model`, `status` |
| `uopenai_tokens_total` | Counter | `type` (prompt/completion), `model` |
| `uopenai_stream_duration_seconds` | Histogram | `model` |
| `uopenai_first_token_latency_seconds` | Histogram | `model` |
| `uopenai_errors_total` | Counter | `endpoint`, `error_type` |

## Compatibility Notes

- **Not supported**: Fine-tuning API, Assistants API, Batch API, Files API, Images API (DALL-E), Audio API (Whisper/TTS)
- **Extensions**: `/v1/rerank`, `/v1/moderations`, `/v1/usage` are Tattva-specific
- **Model list**: `GET /v1/models` returns mapped models with Tattva metadata

## Status

🔴 **Planned** — Endpoint mapping defined, translation logic pending `uai` integration.