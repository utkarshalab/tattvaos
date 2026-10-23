# serve/userve — Core Serving Engine

> Request lifecycle, routing, and connection management for Utkarsha OS serving layer.

## Responsibility

- Accept connections from protocol adapters (`uhttp`, `ugrpc`, `uws`)
- Manage request lifecycle: ingestion → routing → domain handling → streaming → completion
- Enforce timeouts, cancellation, request/response size limits
- Coordinate with `ulb` for worker selection and health-aware routing
- Emit structured events for `uaudit`

## Non-Responsibility

- **Protocol framing** → `uhttp`/`ugrpc`/`uws`
- **Authentication** → `uauth`
- **Firewall/IP policy** → `niti`
- **Audit logging** → `uaudit`
- **Streaming framing** → `ustream`
- **Domain logic** → domain adapters (`uapp`, `uweb`, `uai`, `ustore`, `usys`)

## Interface

```rust
pub struct RequestContext {
    pub request_id: RequestId,
    pub client_identity: Identity,
    pub route: MatchedRoute,
    pub deadline: Deadline,
    pub cancellable: CancellationToken,
    pub metadata: MetadataMap,
}

pub trait DomainAdapter: Send + Sync {
    fn route_prefix(&self) -> &str;
    fn handle(&self, ctx: RequestContext, req: Request) -> ResponseStream;
    fn health(&self) -> HealthStatus;
    fn required_capabilities(&self) -> Vec<Capability>;
}

pub struct Server {
    pub router: Router<Box<dyn DomainAdapter>>,
    pub limits: Limits,
    pub streamer: Streamer,  // from ustream
}

impl Server {
    pub fn handle_connection(&self, conn: Connection, proto: ProtocolAdapter);
}
```

## Request Lifecycle

```
Connection Accepted (uhttp/ugrpc/uws)
         │
         ▼
┌────────────────────────────────────┐
│ Parse Request Headers/Metadata     │
│ Extract: path, method, headers     │
└────────────────┬───────────────────┘
                 │
                 ▼
┌────────────────────────────────────┐
│ ugate: Route Matching              │
│   match path → DomainAdapter       │
│   extract path params              │
└────────────────┬───────────────────┘
                 │
                 ▼
┌────────────────────────────────────┐
│ Create RequestContext              │
│   request_id, identity, deadline   │
│   cancellation token               │
└────────────────┬───────────────────┘
                 │
                 ▼
┌────────────────────────────────────┐
│ DomainAdapter::handle(ctx, req)    │
│   Returns ResponseStream           │
└────────────────┬───────────────────┘
                 │
         ┌───────┴───────┐
         ▼               ▼
   Streaming          Non-streaming
   (ustream)          (single response)
         │               │
         └───────┬───────┘
                 │
                 ▼
┌────────────────────────────────────┐
│ ustream: Frame & Send              │
│   SSE / Chunked / WebSocket        │
│   Backpressure handling            │
│   Client disconnect detection      │
└────────────────┬───────────────────┘
                 │
                 ▼
         Complete / Error
                 │
                 ▼
         uaudit: Log completion
```

## Configuration

```rust
pub struct Limits {
    pub max_request_size: usize,      // default: 32MB
    pub max_response_size: usize,     // default: 1GB (streaming)
    pub request_timeout: Duration,    // default: 30s
    pub stream_idle_timeout: Duration, // default: 60s
    pub max_concurrent_requests: usize, // per worker
    pub max_headers: usize,           // default: 100
    pub max_header_size: usize,       // default: 8KB
}
```

## Integration

- **Upstream**: `uhttp`, `ugrpc`, `uws` (protocol adapters)
- **Downstream**: `ugate` (routing), `ulb` (worker selection), `ustream` (framing)
- **Observability**: Emits `RequestEvent` for `uaudit`

## Status

🟡 **Design Phase** — Interface defined, implementation pending.