# serve — OS Serving Layer

> The unified request serving layer for Utkarsha OS.
> Handles all inbound traffic: apps, browsers, hosted services, AI inference, system APIs.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        serve/                                   │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐             │
│  │  niti   │──▶│  ugate  │──▶│  uauth  │──▶│ uaudit  │  (ingress)│
│  │ firewall│   │ gateway │   │  auth   │   │  audit  │             │
│  └─────────┘  └────┬────┘  └────┬────┘  └────┬────┘             │
│                    │            │            │                   │
│         ┌──────────┼────────────┼────────────┼──────────┐       │
│         ▼          ▼            ▼            ▼          ▼       │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    userve (core)                        │   │
│  │  Request lifecycle • Routing • Streaming • Connections  │   │
│  └────────────────────────────┬────────────────────────────┘   │
│                               │                                │
│         ┌─────────────────────┼─────────────────────┐          │
│         ▼                     ▼                     ▼          │
│  ┌─────────────┐      ┌─────────────┐       ┌─────────────┐   │
│  │   ulb       │      │  ustream    │       │  uhttp      │   │
│  │ load balance│      │  streaming  │       │  protocol   │   │
│  └─────────────┘      └─────────────┘       └─────────────┘   │
│                               │                                │
│         ┌─────────────────────┼─────────────────────┐          │
│         ▼                     ▼                     ▼          │
│  ┌─────────────┐      ┌─────────────┐       ┌─────────────┐   │
│  │  uapp       │      │  uweb       │       │  uai        │   │
│  │  (apps)     │      │ (browsers)  │       │  (inference)│   │
│  └─────────────┘      └─────────────┘       └─────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

---

## Project Categories

### Core Infrastructure (Required)

| Project | Description |
|---------|-------------|
| [`userve/`](userve/) | Core serving engine — request lifecycle, routing, connection management |
| [`ugate/`](ugate/) | API gateway — path routing, rate limiting, validation, circuit breaking |
| [`ulb/`](ulb/) | Load balancer — distributes requests across workers/nodes |
| [`uauth/`](uauth/) | Authentication — API keys, JWT, mTLS, token introspection, RBAC |
| [`uaudit/`](uaudit/) | Audit log — request logging, compliance, tracing, export |
| [`ustream/`](ustream/) | Streaming — SSE, chunked encoding, WebSocket, backpressure |
| [`uhttp/`](uhttp/) | HTTP/1.1, HTTP/2, HTTP/3 protocol handling |
| [`niti/`](niti/) | Firewall — IP policy, geo-blocking, DDoS mitigation, pattern filtering |

### Domain Adapters (Pluggable)

| Project | Description | Upstream |
|---------|-------------|----------|
| [`uapp/`](uapp/) | Native app serving — capability routing, sandbox IPC | `apps/` |
| [`uweb/`](uweb/) | Browser/hosted app serving — DOM streaming, WASM, Service Workers | `browser/`, `hosted/` |
| [`uai/`](uai/) | AI inference serving — model routing, KV cache, batching | `ai/uinfer` |
| [`ustore/`](ustore/) | Object/storage serving — S3-compatible, range requests, resumable | `storage/` |
| [`usys/`](usys/) | System API serving — kernel metrics, config, debugging | `kernel/` |

### AI-Specific Endpoints (Optional)

| Project | Description |
|---------|-------------|
| [`uopenai/`](uopenai/) | OpenAI-compatible API — `/v1/chat/completions`, `/v1/embeddings` |
| [`uembedding/`](uembedding/) | Embedding endpoint — vector generation, batch encoding |
| [`urerank/`](urerank/) | Reranking endpoint — cross-encoder scoring |

---

## Design Principles

1. **Protocol-agnostic core** — `userve` knows nothing about HTTP, gRPC, WebSocket; `uhttp`/`ugrpc`/`uws` are adapters
2. **Domain-adapter pattern** — Each domain (apps, web, AI, storage) plugs in via a standard interface
3. **Composable middleware** — `ugate` chains: niti → uauth → uaudit → route → domain
4. **Streaming-first** — `ustream` is the primitive; request/response is a degenerate stream
5. **Zero-trust ingress** — Every request passes through `niti` + `uauth` + `uaudit` before routing
6. **Horizontal scalability** — `ulb` enables stateless workers; session affinity via consistent hashing

---

## Request Flow

```
Client Request
     │
     ▼
┌────────────────────────────────────────┐
│ niti (firewall)                        │  ── IP policy, rate limit, geo-block
│   allow? ──No──▶ 403                   │
└────────────────┬───────────────────────┘
                 │ Yes
                 ▼
┌────────────────────────────────────────┐
│ uauth (authentication)                 │  ── API key, JWT, mTLS, OIDC
│   valid? ──No──▶ 401                   │
└────────────────┬───────────────────────┘
                 │ Valid
                 ▼
┌────────────────────────────────────────┐
│ uaudit (audit log)                     │  ── Record: timestamp, identity, route
└────────────────┬───────────────────────┘
                 │
                 ▼
┌────────────────────────────────────────┐
│ ugate (gateway routing)                │  ── Path match → domain adapter
│   /api/app/*     ──▶ uapp              │
│   /api/web/*     ──▶ uweb              │
│   /api/ai/*      ──▶ uai               │
│   /api/store/*   ──▶ ustore            │
│   /api/sys/*     ──▶ usys              │
└────────────────┬───────────────────────┘
                 │
                 ▼
┌────────────────────────────────────────┐
│ userve (core engine)                   │  ── Lifecycle, timeouts, cancellation
│   ┌────────────────────────────────┐   │
│   │ Domain Adapter (uapp/uweb/uai) │   │
│   │   handle(request) → stream     │   │
│   └────────────────────────────────┘   │
└────────────────┬───────────────────────┘
                 │
                 ▼
┌────────────────────────────────────────┐
│ ustream (streaming)                    │  ── SSE / chunked / WebSocket frames
│   backpressure, disconnect detection   │
└────────────────┬───────────────────────┘
                 │
                 ▼
┌────────────────────────────────────────┐
│ uhttp (protocol)                       │  ── HTTP/1.1, h2, h3 framing
└────────────────┬───────────────────────┘
                 │
                 ▼
          Client Response
```

---

## Domain Adapter Interface

Every domain adapter implements:

```rust
trait DomainAdapter {
    /// Route key for ugate matching (e.g., "/api/ai")
    fn route_prefix(&self) -> &str;

    /// Handle a request, return a response stream
    fn handle(&self, ctx: RequestContext, req: Request) -> ResponseStream;

    /// Health check for load balancer
    fn health(&self) -> HealthStatus;

    /// Capability requirements (for sandbox enforcement)
    fn required_capabilities(&self) -> Vec<Capability>;
}
```

---

## Configuration

```toml
# serve.toml
[server]
bind = "0.0.0.0:8080"
workers = 0  # 0 = auto (CPU count)
protocol = "http2"  # http1, http2, http3

[ingress]
firewall = { enabled = true, policy = "default-deny" }
auth = { enabled = true, providers = ["api_key", "jwt", "mtls"] }
audit = { enabled = true, output = "file", path = "/var/log/utkarsha/audit.log" }

[gateway]
routes = [
  { prefix = "/api/app", adapter = "uapp" },
  { prefix = "/api/web", adapter = "uweb" },
  { prefix = "/api/ai", adapter = "uai" },
  { prefix = "/api/store", adapter = "ustore" },
  { prefix = "/api/sys", adapter = "usys" },
]

[load_balancer]
strategy = "latency_weighted"
health_check_interval = "5s"
session_affinity = "consistent_hash"

[streaming]
max_concurrent_streams = 10000
backpressure_threshold = "10MB"
client_timeout = "30s"

[domains.uai]
models = ["llama-3-70b", "llama-3-8b", "embed-v3"]
kv_cache_size = "32GB"
batch_window = "10ms"

[domains.uweb]
wasm_cache_size = "2GB"
service_worker_scope = "/sw/"
dom_streaming = true
```

---

## Integration Points

| Layer | Integration |
|-------|-------------|
| `kernel/` | `usys` exposes `/api/sys/*` for metrics, config, debugging |
| `apps/` | `uapp` routes to app sandbox IPC, capability-based |
| `browser/` | `uweb` handles DOM streaming, WASM fetch, Service Workers |
| `hosted/` | `uweb` serves hosted web apps with isolation |
| `ai/uinfer` | `uai` routes to inference engine with KV cache, batching |
| `storage/` | `ustore` provides S3-compatible object API |
| `net/` | `uhttp`/`ugrpc`/`uws` protocol implementations |

---

## Status

| Project | Status | Notes |
|---------|--------|-------|
| `userve` | 🟡 Design | Core engine spec complete |
| `ugate` | 🟡 Design | Gateway routing spec complete |
| `ulb` | 🟡 Design | LB strategies defined |
| `uauth` | 🟡 Design | Multi-provider auth spec |
| `uaudit` | 🟡 Design | Structured logging format |
| `ustream` | 🟡 Design | SSE/WS/chunked unified |
| `uhttp` | 🔴 Planned | HTTP/1.1, h2, h3 |
| `niti` | 🟡 Design | Firewall rules engine |
| `uapp` | 🔴 Planned | App sandbox integration |
| `uweb` | 🔴 Planned | Browser/hosted serving |
| `uai` | 🔴 Planned | AI inference adapter |
| `ustore` | 🔴 Planned | Object storage API |
| `usys` | 🔴 Planned | System API surface |
| `uopenai` | 🔴 Planned | OpenAI compat layer |
| `uembedding` | 🔴 Planned | Embedding endpoint |
| `urerank` | 🔴 Planned | Reranking endpoint |

---

## Philosophy

> **The serving layer is universal.** It routes requests and streams responses.
> **Domains provide the logic.** Apps, Web, AI, Storage, System — each plugs in.
> **Infrastructure is shared.** Firewall, auth, audit, load balancing, streaming — one implementation for all.