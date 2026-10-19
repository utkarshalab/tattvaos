# serve/usys — System API Serving Adapter

> Domain adapter for serving Tattva OS system APIs: metrics, config, debugging, cluster management.

## Responsibility

- **Metrics exposition** — `/metrics` (Prometheus), `/health`, `/ready`, `/live`
- **Configuration API** — Read/write runtime config, feature flags, feature gates
- **Debugging endpoints** — pprof, tracing, heap dump, goroutine dump, mutex profile
- **Cluster management** — Node membership, leadership, drain, cordon
- **Audit query** — Structured audit log search via `uaudit`
- **Service discovery** — Register/discover services, health endpoints

## Non-Responsibility

- **Authentication** → `uauth` (typically mTLS or admin API key)
- **Firewall** → `niti` (restrict to internal network)
- **Load balancing** → `ulb` (usually single-node or leader-only)
- **Audit logging** → `uaudit` (logs usys access)
- **Protocol framing** → `uhttp`/`ugrpc`

## Architecture

```
Request (ugate → userve)  [Internal network only]
         │
         ▼
┌─────────────────────────────────────────────────────────────┐
│ usys Adapter                                                 │
├─────────────────────────────────────────────────────────────┤
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │ Metrics      │  │ Config       │  │ Debug        │       │
│  │ Collector    │   │ Manager      │   │ Endpoints    │       │
│  │ (Prometheus) │   │ (etcd/consul)│   │ (pprof,      │       │
│  └──────────────┘   └──────────────┘   │  tracing)    │       │
│         │                │             └──────────────┘       │
│         ▼                ▼                  │                  │
│  ┌─────────────────────────────────────────┴──────────────┐   │
│  │              System State Provider                      │   │
│  │  Kernel metrics • Network • Disk • GPU • Runtime        │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## Endpoints

| Path | Method | Description | Auth |
|------|--------|-------------|------|
| `/metrics` | GET | Prometheus metrics scrape | `metrics:read` |
| `/health` | GET | Liveness (process alive) | None |
| `/ready` | GET | Readiness (can serve traffic) | None |
| `/live` | GET | Startup (initialization complete) | None |
| `/config` | GET | Full runtime config dump | `config:read` |
| `/config/{key}` | GET | Single config value | `config:read` |
| `/config/{key}` | PUT | Update config value | `config:write` |
| `/config/{key}` | DELETE | Reset to default | `config:write` |
| `/flags` | GET | Feature flags state | `config:read` |
| `/flags/{name}` | PUT | Toggle feature flag | `config:write` |
| `/debug/pprof/` | GET | pprof index | `debug:pprof` |
| `/debug/pprof/heap` | GET | Heap profile | `debug:pprof` |
| `/debug/pprof/goroutine` | GET | Goroutine dump | `debug:pprof` |
| `/debug/pprof/mutex` | GET | Mutex profile | `debug:pprof` |
| `/debug/pprof/block` | GET | Block profile | `debug:pprof` |
| `/debug/trace` | GET | Execution trace (duration=5s) | `debug:trace` |
| `/debug/vars` | GET | Expvars (Go) / custom vars | `debug:vars` |
| `/cluster/nodes` | GET | Cluster membership | `cluster:read` |
| `/cluster/nodes/{id}` | GET | Node details | `cluster:read` |
| `/cluster/nodes/{id}/drain` | POST | Drain node (stop scheduling) | `cluster:admin` |
| `/cluster/nodes/{id}/cordon` | POST | Cordon node (mark unschedulable) | `cluster:admin` |
| `/cluster/leader` | GET | Current leader (if HA) | `cluster:read` |
| `/audit/query` | POST | Structured audit log query | `audit:read` |
| `/audit/export` | GET | Streaming audit export | `audit:read` |
| `/services` | GET | Service catalog | `service:read` |
| `/services/{name}` | GET | Service instances + health | `service:read` |

## Metrics Collection

```rust
pub struct MetricsConfig {
    pub scrape_interval: Duration,        // 15s
    pub scrape_timeout: Duration,         // 10s
    pub retention: Duration,              // 14d (local), 90d (remote)
    pub remote_write: Vec<RemoteWrite>,   // Thanos, Cortex, Mimir
    pub exemplars: bool,                  // Trace ID linkage
    pub native_histograms: bool,          // Prometheus native histograms
}
```

- **Sources**: `kernel/`, `net/`, `storage/`, `ai/`, `serve/` (all emit Prometheus metrics)
- **Aggregation**: Local Prometheus (embedded) or remote write
- **Cardinality control**: Label enforcement, drop high-cardinality labels

## Config Management

```rust
pub struct ConfigSchema {
    pub key: String,
    pub value_type: ValueType,            // String, Int, Float, Bool, Duration, Bytes, Json
    pub default: Value,
    pub mutable: bool,                    // Runtime changeable
    pub validation: ValidationRule,       // Regex, Range, Enum, Custom
    pub requires_restart: bool,           // If true, signal reload
    pub description: String,
    pub tags: Vec<String>,                // "network", "storage", "ai", "experimental"
}
```

- **Backend**: etcd / Consul / SQL (configurable)
- **Validation**: Schema registry with migration support
- **Rollout**: Canary config changes with automatic rollback on error rate spike

## Debug Endpoints Security

```toml
[usys.debug]
# Require mTLS with SPIFFE ID: spiffe://tattva.io/ns/infra/sa/debugger
require_mtls = true
allowed_spiffe = ["spiffe://tattva.io/ns/infra/sa/*"]

# Or API key with debug scope
api_key_scope = "debug:*"

# Rate limit
rate_limit = { requests = 10, window = "1m" }

# Disable in production (env-specific)
enabled = ${ENV != "production"}
```

## Cluster Management

- **Membership**: Raft-based (etcd/Consul) or gossip (Serf)
- **Leadership**: Single leader for config writes, distributed reads
- **Drain**: Signal `ulb` to stop routing, wait for in-flight, then shutdown
- **Cordon**: Mark unschedulable for maintenance

## Audit Query API

```rust
// POST /audit/query
{
  "time_range": { "start": "2026-10-12T00:00:00Z", "end": "2026-10-12T23:59:59Z" },
  "filters": {
    "identity.sub": "user_123",
    "request.path": { "prefix": "/api/ai" },
    "response.status_code": [401, 403, 500]
  },
  "aggregations": [
    { "field": "response.status_code", "type": "terms", "size": 10 },
    { "field": "execution.duration_ms", "type": "percentiles", "percentiles": [50, 95, 99] }
  ],
  "limit": 1000,
  "cursor": "optional_pagination_cursor"
}
```

## Configuration

```toml
[usys]
# Network binding (internal only!)
bind = "127.0.0.1:9090"  # Or unix:///run/tattva/usys.sock
tls = { cert = "/etc/tattva/certs/usys.crt", key = "/etc/tattva/certs/usys.key" }
mtls = { ca = "/etc/tattva/certs/ca.crt", require = true }

# Metrics
metrics = {
  scrape_interval = "15s"
  retention = "14d"
  remote_write = [
    { url = "https://thanos.tattva.io/api/v1/receive", headers = { "Authorization" = "Bearer ${THANOS_TOKEN}" } }
  ]
}

# Config backend
config = {
  backend = "etcd"  # etcd | consul | sql
  endpoints = ["etcd-1:2379", "etcd-2:2379", "etcd-3:2379"]
  prefix = "/tattva/config"
}

# Debug
debug = {
  enabled = true
  require_mtls = true
  rate_limit = { requests = 10, window = "1m" }
}

# Cluster
cluster = {
  backend = "etcd"
  drain_timeout = "5m"
  health_check_interval = "10s"
}

# Audit query
audit = {
  backend = "loki"  # loki | elasticsearch | s3_parquet
  max_query_duration = "30s"
  max_results = 10000
}
```

## Integration

- **Upstream**: `ugate` (routes `/api/sys/*` here, restricted to internal CIDR via `niti`)
- **Downstream**: `kernel/` (metrics), `net/` (network stats), `storage/` (disk), `ai/` (GPU), `runtime/` (runtime metrics)
- **External**: Prometheus/Thanos (metrics), etcd/Consul (config), Loki/ES (audit), pprof tools (debug)

## Metrics

| Metric | Type | Labels |
|--------|------|--------|
| `usys_requests_total` | Counter | `endpoint`, `status` |
| `usys_config_changes_total` | Counter | `key`, `success` |
| `usys_cluster_nodes` | Gauge | `status` (healthy/draining/cordoned) |
| `usys_debug_sessions_active` | Gauge | `type` (pprof/trace) |
| `usys_audit_queries_total` | Counter | `status` |

## Status

🔴 **Planned** — Endpoint catalog defined, backend integrations pending.