# serve/ugate — API Gateway & Router

> Path-based routing, rate limiting, request validation, and gateway middleware for Tattva OS.

## Responsibility

- **Path routing** — Match request path to domain adapter (`uapp`, `uweb`, `uai`, `ustore`, `usys`)
- **Rate limiting** — Per-identity, per-route, per-IP with token bucket / sliding window
- **Request validation** — Schema validation (JSON Schema, Protobuf), size limits, header normalization
- **Header manipulation** — Add/remove/transform headers (CORS, security, tracing)
- **Circuit breaking** — Failure threshold → open circuit → fallback / reject
- **Upstream selection** — Coordinate with `ulb` for worker selection

## Non-Responsibility

- **Authentication** → `uauth` (runs before gateway)
- **Firewall/IP policy** → `niti` (runs before gateway)
- **Audit logging** → `uaudit` (runs before/after gateway)
- **Streaming framing** → `ustream`
- **Domain logic** → domain adapters

## Architecture

```
Request (from uauth/uaudit)
         │
         ▼
┌─────────────────────────────────────┐
│ Middleware Chain                    │
├─────────────────────────────────────┤
│ 1. RateLimiter (per-route/identity) │
│ 2. RequestValidator (schema/size)   │
│ 3. HeaderNormalizer                 │
│ 4. CorsHandler                      │
│ 5. TraceInjector (request-id, etc)  │
└────────────────┬────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────┐
│ Router                              │
│   match path → DomainAdapter        │
│   extract path params               │
│   apply route middleware            │
└────────────────┬────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────┐
│ CircuitBreaker (per upstream)       │
│   closed → half-open → open         │
│   fallback on open                  │
└────────────────┬────────────────────┘
                 │
                 ▼
         DomainAdapter::handle()
```

## Route Definition

```rust
pub struct Route {
    pub prefix: String,                    // "/api/ai"
    pub adapter: Box<dyn DomainAdapter>,   // uai, uapp, uweb, etc.
    pub middleware: Vec<Middleware>,       // route-specific
    pub rate_limit: Option<RateLimit>,     // override global
    pub circuit_breaker: CircuitBreakerConfig,
    pub timeout: Option<Duration>,
    pub retry: Option<RetryPolicy>,
}

pub struct RateLimit {
    pub requests: u64,
    pub window: Duration,
    pub key: RateLimitKey,  // Identity | IP | Route | Custom
}
```

## Rate Limiting

- **Algorithms**: Token bucket (burst), Sliding window (smooth), Fixed window (simple)
- **Keys**: Identity (API key/JWT sub), IP, Route, Composite
- **Storage**: In-memory (single node), Redis (distributed), `ulb`-coordinated
- **Response**: `429 Too Many Requests` with `Retry-After`, `X-RateLimit-*` headers

## Circuit Breaker

```
┌─────────┐     failures > threshold      ┌──────────┐
│ CLOSED  │ ────────────────────────────▶ │  OPEN    │
│ (normal)│                                 │ (reject) │
└─────────┘                                 └────┬─────┘
       ▲                                         │
       │           timeout                       │
       │  half-open (probe requests)             │
       └─────────────────────────────────────────┘
```

- **Metrics**: Error rate, latency percentile, timeout rate
- **Fallback**: Static response, redirect, alternative adapter, cached response

## Request Validation

```rust
pub enum ValidationRule {
    JsonSchema(Schema),
    Protobuf(MessageDescriptor),
    MaxBodySize(usize),
    RequiredHeaders(Vec<String>),
    ForbiddenHeaders(Vec<String>),
    Custom(Box<dyn Fn(&Request) -> Result<(), ValidationError>>),
}
```

## Header Manipulation

| Operation | Use Case |
|-----------|----------|
| `Add` | Security headers (`CSP`, `HSTS`), tracing (`X-Request-ID`) |
| `Remove` | Internal headers (`X-Internal-*`), sensitive data |
| `Transform` | Normalize `Content-Type`, rewrite `Host`, map auth headers |
| `CORS` | Auto-handle `OPTIONS`, `Access-Control-*` |

## Configuration

```toml
[gateway]
routes = [
  { prefix = "/api/app", adapter = "uapp", rate_limit = { requests = 1000, window = "1m" } },
  { prefix = "/api/web", adapter = "uweb" },
  { prefix = "/api/ai", adapter = "uai", rate_limit = { requests = 100, window = "1m" } },
  { prefix = "/api/store", adapter = "ustore" },
  { prefix = "/api/sys", adapter = "usys", auth_required = false },
]

[rate_limit]
default = { requests = 1000, window = "1m", key = "identity" }
storage = "memory"  # memory | redis | ulb

[circuit_breaker]
failure_threshold = 5
success_threshold = 2
timeout = "30s"
half_open_requests = 3

[validation]
max_body_size = "32MB"
default_schema = "openapi"

[headers]
add = [
  { name = "X-Request-ID", value = "{request_id}" },
  { name = "X-Served-By", value = "{worker_id}" },
]
remove = ["X-Internal-*", "Server"]
cors = { enabled = true, origins = ["*"], methods = ["GET", "POST", "PUT", "DELETE"] }
```

## Integration

- **Upstream**: `uauth` (authenticated identity), `uaudit` (pre/post logging)
- **Downstream**: `userve` (core engine), `ulb` (worker selection)
- **Observability**: Emits `RouteEvent` for `uaudit`

## Status

🟡 **Design Phase** — Routing spec complete, middleware chain defined.