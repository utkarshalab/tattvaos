# serve/niti — Inbound Firewall

> L3/L4/L7 firewall for Utkarsha OS serving layer: IP policy, geo-blocking, rate limiting, DDoS mitigation.

## Responsibility

- **IP Allowlist/Denylist** — CIDR, exact, range matching with priority
- **Geo-blocking** — Country/region/ASN based on MaxMind/DB-IP
- **Rate Limiting (L3/L4)** — Per-IP, per-subnet, per-ASN token bucket
- **Pattern Filtering** — Request signature matching (UA, path, headers, body)
- **DDoS Mitigation** — SYN flood, connection exhaustion, slowloris, amplification
- **TLS Fingerprinting** — JA3/JA3S for bot detection
- **Reputation** — Threat intel integration (AbuseIPDB, CrowdSec, custom)

## Non-Responsibility

- **Authentication** → `uauth` (runs after firewall)
- **Application-rate-limiting** → `ugate` (per-identity, per-route)
- **Audit logging** → `uaudit` (logs firewall decisions)
- **Domain logic** → domain adapters

## Rule Engine

```rust
pub struct FirewallRule {
    pub id: String,
    pub priority: i32,              // Lower = higher priority
    pub action: Action,             // Allow | Deny | Challenge | RateLimit | Log
    pub matchers: Vec<Matcher>,
    pub rate_limit: Option<RateLimit>,
    pub challenge: Option<ChallengeConfig>,
    pub metadata: MetadataMap,      // Tags, description, creator
}

pub enum Action {
    Allow,                          // Continue processing
    Deny { code: u16, message: String },  // 403, custom response
    Challenge { type: ChallengeType },    // JS challenge, CAPTCHA, Proof-of-Work
    RateLimit(RateLimit),           // Throttle but allow
    Log,                            // Log only, continue
}

pub enum Matcher {
    IpCidr(String),                 // "192.168.1.0/24", "2001:db8::/32"
    IpRange(String),                // "192.168.1.10-192.168.1.50"
    Country(String),                // "CN", "RU", "KP" (ISO 3166-1 alpha-2)
    Region(String),                 // "CN-Beijing", "US-CA"
    Asn(u32),                       // 15169 (Google), 16509 (Amazon)
    UserAgent(String),              // Regex: ".*bot.*", ".*curl.*"
    Header(String, String),         // Header name, regex value
    Path(String),                   // Regex: "/admin/.*", "/api/v1/.*"
    Method(String),                 // "GET", "POST", "CONNECT"
    TlsFingerprint(String),         // JA3: "771,4865-4867-4866-49195..."
    GeoIp(GeoIpMatcher),            // Composite: country + region + city
    Reputation(ReputationMatcher),  // Score threshold
    Custom(Box<dyn Fn(&RequestContext) -> bool>),
}

pub struct RateLimit {
    pub requests: u64,
    pub window: Duration,
    pub scope: RateLimitScope,      // Ip | Subnet24 | Subnet48 | Asn | Custom
    pub burst: Option<u64>,         // Token bucket burst allowance
}
```

## Default Rules (Priority Order)

| Priority | Rule | Action | Description |
|----------|------|--------|-------------|
| -1000 | Loopback | Allow | `127.0.0.0/8`, `::1` |
| -900 | Private RFC1918 | Allow | `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16` |
| -800 | Health Checks | Allow | Path `/health`, `/ready`, `/live` |
| -700 | Known Bots (Allow) | Allow | Verified Googlebot, Bingbot via reverse DNS |
| 100 | Denylist (Manual) | Deny | Explicit blocked IPs/CIDRs |
| 200 | Geo-block (Config) | Deny | Configured countries |
| 300 | Bad Reputation | Deny | AbuseIPDB score > 75, CrowdSec blocklist |
| 400 | Suspicious JA3 | Challenge | Known bot fingerprints, curl, python-requests |
| 500 | Path Scanning | RateLimit | `/admin`, `/.env`, `/wp-admin`, `/.git` > 10/min |
| 600 | Slowloris Detection | Deny | Header timeout, incomplete requests |
| 700 | Connection Exhaustion | RateLimit | Per-IP connection limit (default: 100) |
| 800 | Global Rate Limit | RateLimit | Per-IP request limit (default: 1000/min) |
| 900 | Allow All | Allow | Default allow (configurable default-deny) |

## DDoS Mitigation Primitives

| Attack Vector | Detection | Mitigation |
|---------------|-----------|------------|
| SYN Flood | SYN/ESTABLISHED ratio, half-open connections | SYN cookies, rate limit SYN/sec |
| Connection Exhaustion | Active connections per IP/subnet | Per-IP connection limit, slow close |
| Slowloris | Header/body read timeout, partial requests | Request timeout, max header/body size |
| HTTP Flood | Request rate, pattern similarity | Adaptive rate limit, challenge |
| Amplification | Large response / small request ratio | Response size limits, disable reflection |
| TLS Exhaustion | Handshake rate, renegotiation | Handshake rate limit, disable renegotiation |

## Challenge System

```rust
pub enum ChallengeType {
    JavaScript,     // Cookie-based, requires JS execution
    Captcha,        // hCaptcha, Turnstile, reCAPTCHA
    ProofOfWork,    // Hashcash-style, CPU cost
    TlsClientCert,  // Require valid client certificate
}

pub struct ChallengeConfig {
    pub challenge_type: ChallengeType,
    pub difficulty: u32,            // PoW: leading zeros; Captcha: score threshold
    pub ttl: Duration,              // Challenge validity (default: 10m)
    pub cookie_name: String,        // "__Host-niti_challenge"
    pub bypass_on_pass: Duration,   // Skip challenge for this duration
}
```

## Threat Intelligence Integration

```toml
[firewall.threat_intel]
providers = [
  { name = "abuseipdb", api_key = "${ABUSEIPDB_KEY}", confidence_min = 75, cache_ttl = "1h" },
  { name = "crowdsec", lapi_url = "http://crowdsec:8080", cache_ttl = "5m" },
  { name = "custom", url = "https://intel.utkarshaos.com/iocs", format = "json", cache_ttl = "15m" },
]
```

## GeoIP Database

- **Providers**: MaxMind GeoIP2 (Country, City, ASN), DB-IP, IP2Location
- **Updates**: Auto-download weekly, verify checksum, hot-reload
- **Memory**: mmap'd for zero-copy lookups (< 5ms p99)

## Configuration

```toml
[firewall]
mode = "allowlist"  # allowlist | denylist (default: denylist)
default_action = "allow"  # allow | deny (when no rule matches)
rules_file = "/etc/utkarsha/niti/rules.yaml"
hot_reload = true

[firewall.geoip]
database = "maxmind"  # maxmind | dbip | ip2location
path = "/usr/share/geoip/GeoIP2-Country.mmdb"
auto_update = true
update_interval = "7d"
blocked_countries = ["KP", "IR", "SY", "CU"]  # Configurable
blocked_asns = []  # e.g., [15169, 16509] for cloud providers (rare)

[firewall.rate_limit]
per_ip = { requests = 1000, window = "1m", burst = 2000 }
per_subnet24 = { requests = 5000, window = "1m" }
per_asn = { requests = 50000, window = "1m" }
connection_limit_per_ip = 100
connection_limit_per_subnet24 = 500

[firewall.ddos]
syn_flood_protection = true
syn_cookies = true
max_half_open = 10000
slowloris_timeout = "10s"
max_header_size = "8KB"
max_body_size = "32MB"
request_timeout = "30s"

[firewall.tls_fingerprinting]
enabled = true
ja3_database = "/etc/utkarsha/niti/ja3_fingerprints.yaml"
block_known_bots = false  # Challenge instead
challenge_suspicious = true

[firewall.challenges]
default_type = "javascript"  # javascript | captcha | pow | tls_cert
javascript = { cookie_ttl = "10m", bypass_ttl = "1h" }
captcha = { provider = "turnstile", site_key = "${TURNSTILE_SITE_KEY}", secret_key = "${TURNSTILE_SECRET_KEY}", score_threshold = 0.5 }
pow = { difficulty = 20, ttl = "5m" }  # ~1ms CPU per request

[firewall.logging]
log_allowed = false
log_denied = true
log_challenged = true
log_rate_limited = true
include_request_body = false
include_response_body = false
```

## Integration

- **Upstream**: `uhttp`/`ugrpc`/`uws` (earliest middleware, before TLS termination for L3/L4)
- **Downstream**: `uauth` (passes allowed requests), `uaudit` (logs all decisions)
- **External**: MaxMind/DB-IP (GeoIP), AbuseIPDB/CrowdSec (reputation), JA3 database

## Metrics

| Metric | Type | Labels |
|--------|------|--------|
| `niti_requests_total` | Counter | `action` (allow/deny/challenge/ratelimit), `rule_id` |
| `niti_connections_active` | Gauge | `ip`, `subnet` |
| `niti_challenge_issued_total` | Counter | `type` (js/captcha/pow/tls) |
| `niti_challenge_passed_total` | Counter | `type` |
| `niti_geoip_lookups_total` | Counter | `result` (hit/miss/error) |
| `niti_reputation_checks_total` | Counter | `provider`, `result` |

## Status

🟡 **Design Phase** — Rule engine defined, DDoS primitives specified, challenge system designed.