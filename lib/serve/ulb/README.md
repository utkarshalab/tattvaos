# serve/ulb — Load Balancer

> Distributes requests across inference workers, app sandboxes, and service nodes for Tattva OS.

## Responsibility

- **Worker discovery** — Registry of healthy workers (via health checks, service discovery)
- **Routing strategies** — Round-robin, least connections, latency-weighted, consistent hashing
- **Health checking** — Active (HTTP/gRPC probes), passive (error rate observation)
- **Session affinity** — Consistent hashing for sticky sessions (WebSocket, SSE, stateful)
- **Traffic shaping** — Canary, blue-green, shadow traffic, weighted routing
- **Draining** — Graceful worker removal with in-flight request completion

## Non-Responsibility

- **Request parsing/routing** → `ugate` + `userve`
- **Protocol handling** → `uhttp`/`ugrpc`/`uws`
- **Authentication** → `uauth`
- **Domain logic** → domain adapters

## Strategies

| Strategy | Use Case | State Required |
|----------|----------|----------------|
| `round_robin` | Homogeneous stateless workers | None |
| `least_connections` | Variable request latency | Active connection count |
| `latency_weighted` | Heterogeneous workers, latency-sensitive | Rolling latency percentile |
| `consistent_hash` | Stateful (WebSocket, SSE, session) | Hash ring |
| `weighted` | Canary, blue-green, capacity-based | Static weights |

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      LoadBalancer                           │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │  Registry   │  │  Strategy   │  │  Health     │         │
│  │  (workers)  │──▶│  (selector) │  │  Monitor    │         │
│  └─────────────┘  └─────────────┘  └─────────────┘         │
│        │                │                │                   │
│        ▼                ▼                ▼                   │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              WorkerSet per Domain                   │   │
│  │  uai: [worker-1, worker-2, ...]                     │   │
│  │  uapp: [sandbox-1, sandbox-2, ...]                  │   │
│  │  uweb: [browser-node-1, ...]                        │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## Worker Registry

```rust
pub struct Worker {
    pub id: WorkerId,
    pub domain: Domain,           // uai, uapp, uweb, ustore, usys
    pub endpoint: Endpoint,       // http://host:port, unix:///path.sock
    pub capacity: Capacity,       // max_concurrent, model_list, etc.
    pub labels: LabelMap,         // zone, gpu_type, model, version
    pub health: HealthStatus,     // Healthy, Degraded, Unhealthy
    pub stats: WorkerStats,       // active_requests, latency_p50, error_rate
}

pub enum Domain { Uai, Uapp, Uweb, Ustore, Usys }

pub struct Capacity {
    pub max_concurrent: usize,
    pub models: Vec<String>,      // for uai: ["llama-3-70b", "embed-v3"]
    pub memory_gb: u64,
    pub gpu_count: u32,
}
```

## Health Checking

### Active (Probes)
```rust
pub struct HealthCheck {
    pub interval: Duration,       // default: 5s
    pub timeout: Duration,        // default: 2s
    pub path: String,             // "/health", "/ready"
    pub expected_status: u16,     // 200
    pub expected_body: Option<String>,
}
```

### Passive (Observation)
- Track: error rate, latency p99, timeout rate, connection failures
- Trigger: `error_rate > 10%` or `latency_p99 > 5s` → `Degraded`
- Trigger: `error_rate > 50%` or `consecutive_failures > 5` → `Unhealthy`

## Session Affinity

```rust
pub enum AffinityKey {
    Identity(String),      // API key / JWT sub
    Ip(String),            // Client IP
    Cookie(String),        // Named cookie
    Header(String),        // Custom header
    QueryParam(String),    // URL parameter
    Custom(Box<dyn Fn(&Request) -> String>),
}
```

- **Consistent Hashing**: Ketama / Jump Hash for minimal reshuffle on worker changes
- **TLS Session Resumption**: For HTTPS, reuse session tickets
- **WebSocket/SSE**: Mandatory affinity (single connection lifecycle)

## Traffic Shaping

```rust
pub struct TrafficPolicy {
    pub canary: Option<CanaryConfig>,      // 5% to new version
    pub shadow: Option<ShadowConfig>,      // Mirror 10% to v2 (no response)
    pub blue_green: Option<BlueGreenConfig>, // Instant switch
    pub weighted: Vec<WeightedTarget>,     // 80% v1, 20% v2
}

pub struct CanaryConfig {
    pub percentage: f32,          // 0.05 = 5%
    pub key: AffinityKey,         // Consistent assignment
    pub metrics: Vec<String>,     // Track: latency, error_rate
    pub auto_promote: Option<PromoteCriteria>,
}
```

## Graceful Draining

```
Worker marked for removal
         │
         ▼
┌─────────────────────────────────────┐
│ 1. Stop accepting new requests      │  (health = Draining)
│ 2. Wait for in-flight (max 30s)     │
│ 3. Force-close remaining            │
│ 4. Remove from registry             │
└─────────────────────────────────────┘
```

## Configuration

```toml
[load_balancer]
strategy = "latency_weighted"  # round_robin | least_connections | latency_weighted | consistent_hash | weighted
health_check_interval = "5s"
health_check_timeout = "2s"
drain_timeout = "30s"

[registry]
# Static or dynamic (consul, etcd, k8s, file)
source = "static"  # static | consul | etcd | kubernetes | file
static_workers = [
  { id = "ai-1", domain = "uai", endpoint = "http://10.0.1.10:8080", capacity = { max_concurrent = 100, models = ["llama-3-70b"] } },
  { id = "ai-2", domain = "uai", endpoint = "http://10.0.1.11:8080", capacity = { max_concurrent = 100, models = ["llama-3-8b"] } },
  { id = "app-1", domain = "uapp", endpoint = "unix:///run/tattva/app-1.sock", capacity = { max_concurrent = 50 } },
]

[affinity]
default_key = "identity"  # identity | ip | cookie | header | query
cookie_name = "tattva_affinity"
header_name = "X-Affinity-Key"

[traffic_shaping]
# Canary example: 5% to new AI worker version
canary = [
  { domain = "uai", percentage = 0.05, key = "identity", target_label = "version=canary" }
]
```

## Integration

- **Upstream**: `ugate` (requests routed here), service discovery (Consul/etcd/k8s)
- **Downstream**: `userve` (forwards selected worker), `uhttp`/`ugrpc`/`uws` (protocol)
- **Observability**: Emits `BalancerEvent` (selection, health change, drain) for `uaudit`

## Status

🟡 **Design Phase** — Strategies defined, registry interface specified.