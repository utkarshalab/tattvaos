# serve/uweb — Browser & Hosted App Serving Adapter

> Domain adapter for serving web apps, browser extensions, and hosted applications with DOM streaming, WASM, and Service Workers.

## Responsibility

- **DOM Streaming** — Progressive HTML streaming with out-of-order `<script>`/`<style>` injection
- **WASM Serving** — `application/wasm` with streaming compilation, `wasm-gc`, SIMD, threads
- **Service Worker** — Registration, update lifecycle, offline-first, background sync
- **Hosted App Isolation** — Per-origin sandbox, CSP, COOP/COEP, storage partitioning
- **Browser Extension API** — Native messaging, declarative net request, offscreen documents
- **Real-time** — WebSocket, SSE, WebRTC data channels for collaborative apps

## Non-Responsibility

- **Authentication** → `uauth` (provides identity)
- **Firewall** → `niti`
- **Load balancing** → `ulb` (selects browser node)
- **Audit logging** → `uaudit`
- **Protocol framing** → `uhttp`/`uws`/`uhttp3`

## Architecture

```
Request (ugate → userve)
         │
         ▼
┌─────────────────────────────────────────────────────────────┐
│ uweb Adapter                                                 │
├─────────────────────────────────────────────────────────────┤
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │ Origin       │  │ WASM         │  │ Service      │       │
│  │ Router       │──▶│ Pipeline     │──▶│ Worker Mgr   │       │
│  │ (host → app) │   │ (compile/    │   │ (register/   │       │
│  └──────────────┘   │  instantiate)│   │  update)     │       │
│         │           └──────────────┘   └──────────────┘       │
│         ▼                     │                │              │
│  ┌─────────────────────────────┴────────────────┴──────┐     │
│  │              Browser Node Pool (ulb)                │     │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐             │     │
│  │  │ Headless│  │ Headless│  │  ...    │             │     │
│  │  │ Chrome  │  │ Firefox │  │         │             │     │
│  │  │ (CDP)   │  │ (BiDi)  │  │         │             │     │
│  │  └─────────┘  └─────────┘  └─────────┘             │     │
│  └─────────────────────────────────────────────────────┘     │
└─────────────────────────────────────────────────────────────┘
```

## Origin Routing

```rust
pub struct WebAppManifest {
    pub origin: Origin,                   // "https://app.example.com"
    pub entrypoint: Url,                  // "/index.html" or "/shell.html"
    pub manifest_url: Url,                // "/manifest.webmanifest"
    pub service_worker: Option<SwConfig>,
    pub wasm_modules: Vec<WasmModule>,
    pub permissions: WebPermissions,
    pub csp: ContentSecurityPolicy,
    pub isolation: IsolationLevel,        // Site | Origin | App
}

pub struct WasmModule {
    pub route: String,                    // "/wasm/app.wasm"
    pub compile_streaming: bool,          // true: WebAssembly.compileStreaming
    pub imports: WasmImports,             // WASI, JSPI, custom
    pub features: WasmFeatures,           // simd, threads, gc, tail-call
    pub cache_key: String,                // Content hash for caching
}
```

## DOM Streaming

```html
<!-- Shell streams immediately -->
<!DOCTYPE html>
<html>
<head>
  <title>App</title>
  <link rel="preload" as="script" href="/wasm/app.wasm">
  <script type="module" src="/js/bootstrap.js"></script>
</head>
<body>
  <div id="app">
    <!-- Streamed fragments inserted here -->
    <template stream:slot="header"><header>...</header></template>
    <template stream:slot="feed"><feed>...</feed></template>
  </div>
</html>
```

- **Streaming parser**: Browser-compatible HTML streaming parser (like `hyperstream`)
- **Out-of-order**: `<script stream:defer>` executes when ready, not blocking
- **Selective hydration**: Islands architecture — hydrate interactive parts only

## WASM Pipeline

```
Fetch /wasm/app.wasm (streaming)
         │
         ▼
┌─────────────────────────────────────┐
│ WebAssembly.compileStreaming()      │  (or instantiateStreaming)
│   - SIMD, threads, GC enabled       │
│   - Memory64 for large heaps        │
└────────────────┬────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────┐
│ Module Cache (IndexedDB + Memory)   │
│   Key: content hash (SHA-256)       │
│   Value: Compiled Module + Imports  │
└────────────────┬────────────────────┘
                 │
                 ▼
        Instantiate with imports
        (WASI, JSPI, custom host functions)
```

- **Tiered compilation**: Fast Liftoff → Optimized TurboFan
- **Cache**: Compiled modules in IndexedDB (persistent) + memory (hot)
- **Streaming compilation**: Start compiling before download complete

## Service Worker Lifecycle

```
Registration (navigator.serviceWorker.register('/sw.js'))
         │
         ▼
Installing → (fetch + cache static assets) → Installed
         │
         ▼
Waiting (skipWaiting?) → Activating → (clients.claim) → Active
         │
         ▼
Controlling clients → Fetch events → (network-first / stale-while-revalidate)
         │
         ▼
Update found → New SW Installing → (skipWaiting) → Active
```

```rust
pub struct SwConfig {
    pub scope: String,                    // "/app/"
    pub script_url: String,               // "/sw.js"
    pub update_via_cache: UpdateViaCache, // "imports" | "all" | "none"
    pub skip_waiting: bool,
    pub clients_claim: bool,
    pub background_sync: Vec<String>,     // ["sync-tasks", "sync-data"]
    pub periodic_sync: Vec<PeriodicSync>, // { tag: "daily", min_interval: "24h" }
    pub push: PushConfig,
}
```

## Hosted App Isolation

| Level | CSP | COOP | COEP | Storage |
|-------|-----|------|------|---------|
| `Site` | `frame-ancestors 'self'` | `same-origin` | `require-corp` | Partitioned by eTLD+1 |
| `Origin` | `default-src 'self'` | `same-origin` | `require-corp` | Partitioned by origin |
| `App` | `default-src 'none'; script-src 'self' 'wasm-unsafe-eval'` | `same-origin` | `require-corp` | Ephemeral, cleared on unload |

## Browser Extension Support

```rust
pub struct ExtensionManifest {
    pub id: String,                       // "extension_id"
    pub version: String,
    pub manifest_version: 3,
    pub background: BackgroundConfig,     // service_worker | offscreen
    pub permissions: Vec<String>,         // ["nativeMessaging", "declarativeNetRequest"]
    pub host_permissions: Vec<String>,    // ["https://api.example.com/*"]
    pub content_scripts: Vec<ContentScript>,
    pub web_accessible_resources: Vec<WebAccessibleResource>,
}
```

- **Native Messaging**: Connect to `uapp` sandbox via stdio over WebSocket
- **Declarative Net Request**: Rules served via `uweb` for ad-blocking, privacy
- **Offscreen Documents**: Long-running tasks, DOM parsing, media recording

## Configuration

```toml
[uweb]
# Browser node pool
browser_nodes = [
  { id = "chrome-1", endpoint = "ws://10.0.2.10:9222", protocol = "cdp", capacity = 50 },
  { id = "firefox-1", endpoint = "ws://10.0.2.11:6000", protocol = "bidi", capacity = 30 },
]

# DOM Streaming
dom_streaming = {
  enabled = true
  parser_buffer = "64KB"
  fragment_timeout = "5s"
  selective_hydration = true
}

# WASM
wasm = {
  streaming_compile = true
  cache_dir = "/var/cache/utkarsha/wasm"
  max_cache_size = "2GB"
  features = ["simd", "threads", "gc", "tail_call", "memory64"]
  wasi_preview1 = true
  wasi_preview2 = true
}

# Service Worker
service_worker = {
  scope = "/sw/"
  update_check_interval = "1h"
  skip_waiting_default = true
  clients_claim_default = true
}

# Isolation
isolation = {
  default_level = "origin"  # site | origin | app
  csp_report_only = false
  coep = "require-corp"
  coop = "same-origin"
  storage_partitioning = true
}

# Extensions
extensions = {
  enabled = true
  native_messaging_host = "uapp"  # Route to uapp adapter
  dnr_rules_max = 50000
  offscreen_max_concurrent = 10
}
```

## Integration

- **Upstream**: `ugate` (routes `/api/web/*` here), `ulb` (selects browser node)
- **Downstream**: `ubrowser` (CDP/BiDi protocol), `uwasm` (WASM runtime), `usw` (Service Worker runtime)
- **External**: `hosted/` registry (web app manifests), `browser/` (browser binary management)

## Metrics

| Metric | Type | Labels |
|--------|------|--------|
| `uweb_requests_total` | Counter | `origin`, `status` |
| `uweb_dom_stream_duration_seconds` | Histogram | `origin` |
| `uweb_wasm_compile_duration_seconds` | Histogram | `module`, `cached` |
| `uweb_sw_registrations_total` | Counter | `origin`, `status` |
| `uweb_browser_nodes_active` | Gauge | `browser`, `protocol` |
| `uweb_extension_messages_total` | Counter | `extension_id`, `type` |

## Status

🔴 **Planned** — Architecture defined, browser protocol integration pending `ubrowser`.