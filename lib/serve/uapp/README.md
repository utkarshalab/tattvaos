# serve/uapp — Native App Serving Adapter

> Domain adapter for serving native Tattva OS applications via capability-routed sandbox IPC.

## Responsibility

- **Capability-based routing** — Map request to app sandbox via capability tokens
- **Sandbox IPC** — Communicate with app sandbox over `uipc` (Unix domain sockets, vsock)
- **Lifecycle management** — Start/stop/suspend apps on demand
- **Resource accounting** — CPU, memory, GPU, network quotas per app
- **Streaming support** — SSE, WebSocket for real-time app communication
- **File serving** — Static assets, WASM bundles, app manifests

## Non-Responsibility

- **Authentication** → `uauth` (provides identity + capabilities)
- **Firewall** → `niti`
- **Load balancing** → `ulb` (selects app sandbox node)
- **Audit logging** → `uaudit`
- **Protocol framing** → `uhttp`/`uws`

## Architecture

```
Request (ugate → userve)
         │
         ▼
┌─────────────────────────────────────────────────────────────┐
│ uapp Adapter                                                 │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────┐  │
│  │ Capability      │  │ Sandbox         │  │ Resource    │  │
│  │ Router          │──▶│ Manager         │──▶│ Accountant  │  │
│  │ (token → app)   │   │ (start/stop/    │   │ (quotas,    │  │
│  └─────────────────┘   │  IPC connect)   │   │  limits)    │  │
│                        └────────┬────────┘   └─────────────┘  │
│                                 │                              │
│                                 ▼                              │
│                        ┌─────────────────┐                     │
│                        │ IPC Transport   │                     │
│                        │ (uipc: unix/vsock)                     │
│                        └────────┬────────┘                     │
└─────────────────────────────────┼──────────────────────────────┘
                                  │
                                  ▼
                         ┌─────────────────┐
                         │ App Sandbox     │
                         │ (wasm/native)   │
                         └─────────────────┘
```

## Capability Routing

```rust
pub struct AppCapability {
    pub app_id: AppId,                    // "com.example.myapp"
    pub version: Version,                 // "1.2.3" or "latest"
    pub capabilities: Vec<Capability>,    // ["net:outbound", "gpu:compute", "fs:data"]
    pub identity: Identity,               // From uauth (user, service, device)
    pub params: HashMap<String, String>,  // Route params, query, config
}
```

- **Capability token**: Signed JWT or Macaroon from `uauth` encoding allowed apps + resources
- **Route pattern**: `/api/app/{app_id}/*` → extracts `app_id`, matches capability
- **Version resolution**: `latest`, semver range, or exact; falls back to default channel

## Sandbox Manager

```rust
pub struct SandboxSpec {
    pub app_id: AppId,
    pub version: Version,
    pub runtime: Runtime,                 // WasmComponent | NativeElf | Container
    pub entrypoint: String,               // "main", "handler", "serve"
    pub resources: ResourceLimits,
    pub environment: EnvMap,
    pub mounts: Vec<Mount>,               // /data, /config, /tmp, /dev/gpu
    pub network: NetworkPolicy,           // None | Loopback | Egress | Ingress
}

pub struct ResourceLimits {
    pub cpu_shares: u32,                  // CFS shares (1024 = 1 CPU)
    pub memory_bytes: u64,                // Hard limit
    pub gpu_devices: Vec<GpuDevice>,      // Specific GPU UUIDs or count
    pub disk_bytes: u64,                  // Ephemeral storage
    pub pids_max: u32,                    // Process limit
}
```

## IPC Protocol (uipc)

```
App Request (from uapp)                    App Response
┌─────────────────────────────────┐       ┌─────────────────────────────────┐
│ AppRequest {                    │       │ AppResponse {                   │
│   request_id: Uuid,             │       │   request_id: Uuid,             │
│   method: "GET" | "POST" | ..., │       │   status: 200,                  │
│   path: "/api/data",            │       │   headers: {...},               │
│   headers: HeaderMap,           │       │   body: Stream<Bytes>,          │
│   body: Stream<Bytes>,          │       │   trailers: HeaderMap,          │
│   capabilities: Vec<Cap>,       │       │   error: Option<AppError>,      │
│   identity: Identity,           │       │ }                               │
│ }                               │       └─────────────────────────────────┘
└─────────────────────────────────┘
         │                                    │
         ▼                                    ▼
    Unix Domain Socket                   Unix Domain Socket
    (abstract: @tattva/app/{app_id})     (same socket, bidirectional)
```

- **Streaming**: Both request/body and response/body are streamed
- **Backpressure**: Credit-based flow control over uipc
- **Cancellation**: Explicit `CANCEL` frame propagates to app

## App Lifecycle

```
Request for app_id
         │
         ▼
┌─────────────────────────────────────┐
│ SandboxManager.get_or_start(app)    │
├─────────────────────────────────────┤
│ Running?  ──Yes──▶ Return sandbox   │
│   │                                 │
│   No                                │
│   ▼                                 │
│ Resolve version (latest/semver)     │
│   │                                 │
│   ▼                                 │
│ Check resource quota                │
│   │                                 │
│   ▼                                 │
│ Allocate resources (cpu, mem, gpu)  │
│   │                                 │
│   ▼                                 │
│ Create sandbox (wasm/native/container)                          │
│   │                                 │
│   ▼                                 │
│ Start process, establish uipc       │
│   │                                 │
│   ▼                                 │
│ Health check (/health endpoint)     │
│   │                                 │
│   ▼                                 │
│ Register with ulb, return sandbox   │
└─────────────────────────────────────┘
```

## Static Asset Serving

- **Manifest**: `app.toml` declares `assets = { "/static" = "dist", "/wasm" = "pkg" }`
- **Caching**: `Cache-Control: immutable, max-age=31536000` for content-hashed files
- **Compression**: Pre-compressed `.gz`, `.br` served when `Accept-Encoding` matches
- **WASM**: `application/wasm` with `Cross-Origin-Embedder-Policy: require-corp`

## Configuration

```toml
[uapp]
# Sandbox runtime preference order
runtimes = ["wasm_component", "native_elf", "container"]

# Default resource limits (overridden per-app)
default_limits = { cpu_shares = 1024, memory_bytes = 536870912, disk_bytes = 1073741824 }

# Sandbox pool (pre-warmed)
pool = {
  min_ready = 2,
  max_idle = 10,
  idle_timeout = "5m",
  prewarm_apps = ["com.tattva.terminal", "com.tattva.files"]
}

# IPC
ipc = {
  transport = "unix"  # unix | vsock
  socket_dir = "/run/tattva/app"
  connect_timeout = "2s"
  request_timeout = "30s"
}

# Asset serving
assets = {
  enabled = true
  cache_control = "public, max-age=31536000, immutable"
  precompressed = ["gzip", "brotli"]
  index_fallback = "index.html"  # SPA support
}

# Health checks
health = {
  path = "/health"
  interval = "10s"
  timeout = "2s"
  failure_threshold = 3
}
```

## Integration

- **Upstream**: `ugate` (routes `/api/app/*` here), `ulb` (selects node with capacity)
- **Downstream**: `uipc` (sandbox communication), `uruntime` (wasm/native/container)
- **External**: `apps/` registry (manifests, versions), `capabilities/` (token validation)

## Metrics

| Metric | Type | Labels |
|--------|------|--------|
| `uapp_requests_total` | Counter | `app_id`, `status` |
| `uapp_sandbox_starts_total` | Counter | `app_id`, `runtime` |
| `uapp_sandbox_active` | Gauge | `app_id`, `node` |
| `uapp_ipc_latency_seconds` | Histogram | `app_id` |
| `uapp_resource_usage` | Gauge | `app_id`, `resource` (cpu/mem/gpu/disk) |

## Status

🔴 **Planned** — Interface defined, sandbox integration pending `uruntime`/`uipc`.