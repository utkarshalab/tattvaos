# serve/uaudit — Audit Logging

> Structured, tamper-evident request audit logging for Tattva OS serving layer.

## Responsibility

- **Request recording** — Every inbound request with full context
- **Structured output** — JSON Lines, protobuf, or custom format
- **Tamper evidence** — Hash chaining, Merkle tree, optional signing
- **Compliance** — GDPR, SOC2, HIPAA field controls, retention policies
- **Export** — Streaming to SIEM, object storage, log aggregation
- **Query** — Time-range, identity, route, status code filtering

## Non-Responsibility

- **Authentication decisions** → `uauth` (logs the decision)
- **Rate limiting** → `ugate` (logs the limit)
- **Firewall blocks** → `niti` (logs the block)
- **Application logs** → domain adapters (separate stream)

## Event Schema

```json
{
  "version": "1.0",
  "event_id": "evt_01h8j9k2m3n4p5q6r7s8t9v0w1",
  "timestamp": "2026-10-12T14:32:15.123456Z",
  "request": {
    "request_id": "req_01h8j9k2m3n4p5q6r7s8t9v0w1",
    "method": "POST",
    "path": "/api/ai/v1/chat/completions",
    "route": "/api/ai/*",
    "domain": "uai",
    "protocol": "http2",
    "client_ip": "203.0.113.42",
    "user_agent": "tattva-sdk/1.2.0",
    "request_size": 2048,
    "headers": { "content-type": "application/json", "authorization": "Bearer [REDACTED]" }
  },
  "identity": {
    "sub": "user_123",
    "iss": "https://auth.tattva.io",
    "auth_method": "Jwt",
    "scopes": ["inference:chat"],
    "roles": ["developer"],
    "org_id": "org_456",
    "tier": "premium"
  },
  "routing": {
    "gateway_matched": true,
    "rate_limited": false,
    "circuit_breaker": "closed",
    "selected_worker": "ai-worker-7",
    "worker_domain": "uai",
    "affinity_key": "identity:user_123"
  },
  "execution": {
    "started_at": "2026-10-12T14:32:15.123456Z",
    "completed_at": "2026-10-12T14:32:17.456789Z",
    "duration_ms": 2333,
    "streaming": true,
    "first_token_ms": 156,
    "tokens_generated": 247,
    "model": "llama-3-70b",
    "status": "completed"
  },
  "response": {
    "status_code": 200,
    "response_size": 15632,
    "compressed": true,
    "cache_status": "miss"
  },
  "errors": null,
  "compliance": {
    "pii_detected": false,
    "data_classification": "internal",
    "retention_days": 2555
  },
  "integrity": {
    "hash": "sha256:a1b2c3d4...",
    "chain_hash": "sha256:f0e1d2c3...",
    "sequence": 12847392
  }
}
```

## Redaction Rules

| Field | Action |
|-------|--------|
| `Authorization` header | `[REDACTED]` |
| `Cookie` header | `[REDACTED]` |
| `X-API-Key` header | `[REDACTED]` |
| Request body (if `pii=true`) | Hash only |
| Response body (if `pii=true`) | Hash only |
| JWT claims (configurable) | Keep `sub`, `roles`, `scopes`; drop `email`, `name` |

## Output Targets

| Target | Format | Use Case |
|--------|--------|----------|
| **File (local)** | JSON Lines | Development, single-node |
| **File (rotated)** | JSON Lines + gzip | Production single-node |
| **Syslog / journald** | RFC 5424 | System integration |
| **Kafka / Pulsar** | JSON / Protobuf | High-volume, streaming SIEM |
| **Object Storage (S3)** | Parquet / ORC | Long-term retention, analytics |
| **Elasticsearch / OpenSearch** | JSON | Search, dashboards |
| **Loki** | JSON | Log aggregation |
| **Custom** | Plugin | Any destination |

## Tamper Evidence

### Hash Chaining
```
Event N:   hash_N = SHA256(event_N || chain_hash_{N-1})
chain_hash_N = hash_N
```
- Each event includes `chain_hash` linking to previous
- Verification: Recompute chain from genesis

### Merkle Tree (Batch)
```
Batch of 1000 events → Merkle root → Signed by HSM/KMS
Root published to transparency log / blockchain anchor
```

### Optional Signing
```toml
[audit.integrity]
signing = true
kms_key_id = "arn:aws:kms:us-east-1:123456789:key/..."
sign_algorithm = "ECDSA_P256"
sign_batch_size = 1000
```

## Compliance Features

| Regulation | Feature |
|------------|---------|
| **GDPR** | `right_to_erasure` — purge by `sub`; `data_minimization` — configurable fields |
| **SOC2** | `audit_trail` — immutable, timestamped, sequenced |
| **HIPAA** | `phi_detection` — regex/ML scan, auto-redact; `encryption_at_rest` |
| **PCI-DSS** | `pan_detection` — Luhn + regex; `no_sensitive_in_logs` |

## Retention & Lifecycle

```toml
[audit.retention]
default_days = 2555  # 7 years
by_domain = { uai = 3650, uapp = 2555, uweb = 1095, usys = 2555 }
by_classification = { public = 365, internal = 2555, confidential = 3650, restricted = 3650 }
by_status = { error = 3650, denied = 2555 }
archive_after_days = 90
archive_target = "s3://tattva-audit-archive/{domain}/{year}/{month}/"
```

## Configuration

```toml
[audit]
enabled = true
sample_rate = 1.0  # 1.0 = 100%, 0.1 = 10%
buffer_size = 10000
flush_interval = "1s"
max_event_size = "1MB"

[audit.output]
targets = [
  { type = "file", path = "/var/log/tattva/audit.log", rotation = "daily", compression = "gzip" },
  { type = "kafka", brokers = ["kafka-1:9092", "kafka-2:9092"], topic = "tattva.audit", format = "json" },
  { type = "s3", bucket = "tattva-audit", prefix = "audit/", format = "parquet", batch_size = 10000 }
]

[audit.redaction]
headers = ["authorization", "cookie", "x-api-key", "x-csrf-token"]
body_pii_fields = ["email", "phone", "ssn", "credit_card", "address"]
jwt_claims_keep = ["sub", "roles", "scopes", "org_id", "tier"]
jwt_claims_drop = ["email", "name", "picture", "preferred_username"]

[audit.integrity]
hash_chain = true
merkle_tree = false
signing = false
genesis_hash = "sha256:0000000000000000000000000000000000000000000000000000000000000000"
```

## Integration

- **Upstream**: `niti` (firewall events), `uauth` (auth decisions), `ugate` (routing), `userve` (execution), `ustream` (streaming metrics)
- **Downstream**: SIEM, log aggregation, compliance archives
- **Query API**: `/api/sys/audit/query` (via `usys` domain adapter)

## Status

🟡 **Design Phase** — Event schema defined, output targets specified, integrity model designed.