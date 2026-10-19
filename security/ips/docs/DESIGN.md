# ips — Design

## Goals

1. **Fail closed** — If enforcement cannot be verified, traffic is blocked. Default-deny posture is secure-by-default.
2. **Inline enforcement** — IPS sits in the traffic path and can modify/drop packets in real-time.
3. **Default-deny** — No traffic is allowed unless an explicit policy rule permits it.
4. **Composable with IDS** — IDS detects, IPS prevents. IDS alerts feed IPS policy for automated prevention.
5. **Stateful enforcement** — Connection tracking enables context-aware decisions (not just packet-by-packet).
6. **Audit every enforcement** — Every drop/reset/throttle/quarantine/block is logged through `usrauth/audit`.

## Non-Goals

- Passive monitoring only — that is `security/ids/`.
- User-space execution — kernel-only subsystem.
- Long-term alert storage — enforcement events are forwarded to SIEM; local storage is bounded.
- Active response beyond network blocking (session termination, host isolation beyond network) — that is SOAR + incident_response.

## Data Structures (Planned)

All mutable state resides in `.bss`, zero-initialized on load.

### ips_state_base_t (per-component)

```
+---------------------+  <---
| magic: resd 1       |      IPS_STATE_MAGIC for validation
+---------------------+
| version: resd 1     |      component version
+---------------------+
| refcount: resd 1    |      reference count
+---------------------+
| spinlock: resq 1    |      SMP spinlock (STUB)
+---------------------+
| enabled: resb 1     |      component enabled flag
+---------------------+
| pad: resb 7         |      alignment
+---------------------+
| init_ns: resq 1     |      initialization timestamp
+---------------------+
| stats_packets: resq 1|     total packets inspected
+---------------------+
| stats_dropped: resq 1 |     total packets dropped
+---------------------+
| stats_blocked: resq 1 |     total endpoints blocked
+---------------------+
| stats_quarantined: resq 1 | total endpoints quarantined
+---------------------+  <---
```

### ips_enforce_ctx_t (enforcement request input)

```
+---------------------+  <---
| timestamp_ns: resq 1|      enforcement timestamp
+---------------------+
| src_ip: resd 1      |      IPv4 source address
+---------------------+
| dst_ip: resd 1      |      IPv4 destination address
+---------------------+
| src_port: resd 1    |
+---------------------+
| dst_port: resd 1    |
+---------------------+
| protocol: resd 1    |      6=TCP, 17=UDP, 1=ICMP
+---------------------+
| packet_len: resd 1  |      total packet length
+---------------------+
| action_hint: resd 1 |      suggested action (IPS_ACTION_*)
+---------------------+
| reason_hint: resd 1 |      suggested reason (IPS_REASON_*)
+---------------------+
| session_id: resq 1  |      associated session (0 = none)
+---------------------+
| context_ptr: resq 1 |      opaque context blob
+---------------------+
| context_size: resd 1|
+---------------------+
| geoip_country: resd 1|     resolved country code (GeoIP)
+---------------------+
| app_id: resd 1      |      detected application ID (App Control)
+---------------------+
| tls_fingerprint: resq 1|     JA3/JA3S TLS fingerprint (TLS Inspector)
+---------------------+
| domain: resq 1      |      DNS domain (DNS Filter)
+---------------------+
| url_category: resd 1|      URL category (URL Filter)
+---------------------+
| file_hash: resq 1   |      file SHA-256 (File Analysis)
+---------------------+
| bot_score: resd 1   |      bot probability 0-100 (Bot Detector)
+---------------------+
| threat_score: resd 1|      aggregated threat score 0-100
+---------------------+
| reputation_score: resd 1|   IP/domain reputation -100 to 100
+---------------------+  <---
```

### ips_enforce_result_t (enforcement output)

```
+---------------------+  <---
| action: resd 1      |      IPS_ACTION_*
+---------------------+
| reason_code: resd 1 |      IPS_REASON_*
+---------------------+
| duration_ms: resq 1 |      block/quarantine duration (0 = permanent)
+---------------------+
| pad: resd 4         |      alignment
+---------------------+
| enforced_ns: resq 1 |      enforcement timestamp
+---------------------+  <---
```

## State Machines

### 1. IPS Subsystem State Machine

```
    ┌────────────────┐
    │  UNINITIALIZED │
    └───────┬────────┘
            │ ips_init()
            ▼
    ┌────────────────┐      ips_shutdown()      ┌────────────────┐
    │   INITIALIZED  │ ───────────────────────► │   SHUTDOWN   │
    └───────┬────────┘                        └────────────────┘
            │
     ┌──────┴──────┐
     │             │
     ▼             ▼
┌─────────┐   ┌─────────────┐
│ ENABLED │   │   DISABLED  │  ← fail-closed default
└────┬────┘   └─────────────┘
     │
     ▼ packet arrives
┌─────────────────┐
│  ENFORCING      │────┐
└─────────┬─────────┘    │
          │              │
          ▼              │ error/exception
┌─────────────────┐      │
│  ACTION RETURN  │──────┘
└─────────────────┘
```

**State transitions:**

| From → To | Trigger | Condition |
|-----------|---------|-----------|
| UNINITIALIZED → INITIALIZED | `ips_init()` | Returns 0 |
| INITIALIZED → ENABLED | `ips_status()` | Component ready |
| INITIALIZED → SHUTDOWN | `ips_shutdown()` | Teardown |
| ENABLED → DISABLED | Admin action | Explicit disable |
| ENABLED → ENFORCING | Packet arrives | `ips_enforce()` called |
| ENFORCING → ENABLED | Action returned | ALLOW/DROP/RESET/... |
| ENFORCING → SHUTDOWN | Critical failure | Component fault |

### 2. Enforcement Decision State Machine

```
    ┌─────────────────┐
    │   PACKET        │──────────────┐
    │   RECEIVED      │              │
    └─────────┬───────┘              │
              │                      │ component down + fail-closed
              ▼                      ▼
    ┌─────────────────┐   ┌─────────────────┐
    │  BYPASS_CHECK   │   │  ACTION_DROP    │────┐
    │  (fail mode)    │   │  (component     │    │
    └─────────┬───────┘   │  down)         │    │
              │ component │                 │    │
              │ down +    │                 │    │
              │ fail_open │                 │    │
              ▼           ▼                 │    │
    ┌─────────────────┐   ┌─────────────────┐    │
    │  BLOCKLIST_CHECK│   │  ACTION_ALLOW   │────┘
    └─────────┬───────┘   └─────────────────┘
              │ blocked IP
              ▼
    ┌─────────────────┐
    │  QUARANTINE_CHECK│
    └─────────┬───────┘
              │ quarantined
              ▼
    ┌─────────────────┐
    │  RATE_LIMITER   │──────────────┐
    │                 │              │ rate limited
    └─────────┬───────┘              ▼
              │ within limit         ┌─────────────────┐
              ▼                      │  ACTION_THROTTLE│
    ┌─────────────────┐              └─────────────────┘
    │  POLICY_EVAL    │──────────────┐
    │  (5-tuple match)│              │ no match → default DENY
    └─────────┬───────┘              ▼
              │ match DENY           ┌─────────────────┐
              ▼                      │  ACTION_DROP    │
    ┌─────────────────┐              └─────────────────┘
    │  GEOIP_CHECK    │──────────────┐
    │                 │              │ country blocked
    └─────────┬───────┘              ▼
              │ country allowed     ┌─────────────────┐
              ▼                      │  ACTION_DROP    │
    ┌─────────────────┐              └─────────────────┘
    │  APP_CONTROL    │──────────────┐
    │                 │              │ app blocked
    └─────────┬───────┘              ▼
              │ app allowed         ┌─────────────────┐
              ▼                      │  ACTION_DROP    │
    ┌─────────────────┐              └─────────────────┘
    │  TLS_INSPECTOR  │──────────────┐
    │                 │              │ TLS violation
    └─────────┬───────┘              ▼
              │ TLS clean           ┌─────────────────┐
              ▼                      │  ACTION_DROP    │
    ┌─────────────────┐              └─────────────────┘
    │  DNS_FILTER     │──────────────┐
    │                 │              │ domain blocked
    └─────────┬───────┘              ▼
              │ domain allowed      ┌─────────────────┐
              ▼                      │  ACTION_DROP    │
    ┌─────────────────┐              └─────────────────┘
    │  FILE_ANALYSIS  │──────────────┐
    │                 │              │ file malicious
    └─────────┬───────┘              ▼
              │ file clean          ┌─────────────────┐
              ▼                      │  ACTION_DROP    │
    ┌─────────────────┐              └─────────────────┘
    │  URL_FILTER     │──────────────┐
    │                 │              │ URL blocked
    └─────────┬───────┘              ▼
              │ URL allowed         ┌─────────────────┐
              ▼                      │  ACTION_DROP    │
    ┌─────────────────┐              └─────────────────┘
    │  BOT_DETECTOR   │──────────────┐
    │                 │              │ bot detected
    └─────────┬───────┘              ▼
              │ human              ┌─────────────────┐
              ▼                      │  ACTION_THROTTLE│
    ┌─────────────────┐              └─────────────────┘
    │  DDoS_PROTECTOR │──────────────┐
    │                 │              │ DDoS detected
    └─────────┬───────┘              ▼
              │ within limits       ┌─────────────────┐
              ▼                      │  ACTION_DROP    │
    ┌─────────────────┐              └─────────────────┘
    │  THREAT_FEED    │──────────────┐
    │                 │              │ IOC matched
    └─────────┬───────┘              ▼
              │ IOC clean           ┌─────────────────┐
              ▼                      │  ACTION_DROP    │
    ┌─────────────────┐              └─────────────────┘
    │  WAF_ENGINE     │──────────────┐
    │                 │              │ WAF violation
    └─────────┬───────┘              ▼
              │ clean               ┌─────────────────┐
              ▼                      │  ACTION_DROP    │
    ┌─────────────────┐              └─────────────────┘
    │  INSPECTOR      │──────────────┐
    │                 │              │ threat found
    └─────────┬───────┘              ▼
              │ clean               ┌─────────────────┐
              ▼                      │  ACTION_DROP    │
    ┌─────────────────┐              └─────────────────┘
    │  ENFORCER       │──────────────┐
    │  (apply action) │              │
    └─────────┬───────┘              ▼
              │ action applied      ┌─────────────────┐
              ▼                      │  ACTION_RETURN  │
    ┌─────────────────┐              └─────────────────┐
    │  CONN_TRACKER   │                      │           │
    │  (track state)  │                      │           │
    └─────────┬───────┘                      │           │
              │                              │           │
              ▼                              │           │
    ┌─────────────────┐                      │           │
    │  SIEM_EXPORT    │                      │           │
    └─────────┬───────┘                      │           │
              │                              │           │
              ▼                              │           │
    ┌─────────────────┐                      │           │
    │  STATS_RECORD   │                      │           │
    └─────────┬───────┘                      │           │
              │                              │           │
              ▼                              │           │
    ┌─────────────────┐                      │           │
    │  ML_ANOMALY     │                      │           │
    └─────────┬───────┘                      │           │
              │ anomaly detected             │           │
              ▼                              │           │
    ┌─────────────────┐                      │           │
    │  ACTION_RETURN  │──────────────────────┘           │
    └─────────────────┘                                  │
                                                         │
                                                   Caller receives action + reason + duration
```

### 3. Connection State Machine

```
    ┌──────────────┐
    │     NEW      │──────────────────┐
    └───────┬────────┘                │
            │ SYN received            │ connection timeout
            ▼                         ▼
    ┌──────────────┐          ┌──────────────┐
    │ ESTABLISHED  │◀─────────│   INVALID    │
    │   (active)   │          └──────────────┘
    └───────┬────────┘
            │ FIN/RST received
            ▼
    ┌──────────────┐
    │   CLOSED     │
    └──────────────┘
```

**Connection events:**

| Event | From → To | Action |
|-------|-----------|--------|
| New 5-tuple seen | — → NEW | Create connection entry |
| Valid SYN | NEW → ESTABLISHED | Track handshake |
| Data in ESTABLISHED | ESTABLISHED → ESTABLISHED | Update bytes, last_seen |
| FIN/RST | ESTABLISHED → CLOSED | Mark connection closed |
| Timeout | any → CLOSED | Remove from table |

## Enforcement Actions Detail

| Action | Behavior | When Used |
|--------|----------|-----------|
| `IPS_ACTION_ALLOW` | Forward packet normally | Policy permits, no threats detected |
| `IPS_ACTION_DROP` | Silently discard packet | Policy denies, threat detected, blocklist match |
| `IPS_ACTION_RESET` | Inject TCP RST to both sides | Active connection termination needed |
| `IPS_ACTION_THROTTLE` | Rate-limit to reduced bandwidth | Rate limit exceeded, DDoS mitigation |
| `IPS_ACTION_QUARANTINE` | Redirect to quarantine VLAN/proxy | Compromised host, remediation needed |
| `IPS_ACTION_BLOCK` | Block all traffic from/to IP for duration | Repeated violations, manual block |
| `IPS_ACTION_REDIRECT` | Redirect to different destination | Load balancing, honeypot diversion |
| `IPS_ACTION_INSPECT_DEEP` | Send to deep packet inspection | Suspicious traffic needs deeper analysis |
| `IPS_ACTION_SANDBOX` | Send file to sandbox for analysis | Unknown file, behavioral analysis needed |
| `IPS_ACTION_CHALLENGE` | CAPTCHA / challenge-response | Suspected bot, verify human |

## Fail Mode Behavior

| Scenario | IPS_FAIL_CLOSED | IPS_FAIL_OPEN |
|----------|-----------------|---------------|
| Component down | All traffic BLOCKED | All traffic ALLOWED |
| Inspector crash | Traffic dropped | Traffic allowed (risky) |
| Policy engine down | Traffic dropped | Traffic allowed (risky) |
| Enforcer crash | Traffic dropped | Traffic allowed (risky) |
| Use case | Secure networks, sensitive assets | HA paths, availability-critical |

## Deny Reason Attribution

Every DENY action carries a reason code so audit logs explain WHY:

```
IPS_REASON_BLACKLISTED_IP   → Source/dest IP is on blocklist
IPS_REASON_POLICY_VIOLATION → No allow rule matches (default-deny)
IPS_REASON_RATE_LIMIT       → Requests per second exceeded threshold
IPS_REASON_IDS_ALERT        → IDS detected threat, IPS blocking
IPS_REASON_PROTOCOL_VIOLATION → Malformed protocol traffic
IPS_REASON_QUARANTINED_HOST → Endpoint is in quarantine
IPS_REASON_CONNECTION_LIMIT → Max connections per IP exceeded
IPS_REASON_COMPONENT_DOWN   → Enforcement component unavailable (fail-closed)
IPS_REASON_INVALID_REQUEST  → Malformed enforcement request
IPS_REASON_GEOIP_BLOCKED    → Source/destination country is blocked
IPS_REASON_APP_BLOCKED      → Application not in allowlist
IPS_REASON_TLS_VIOLATION    → TLS certificate/fingerprint violation
IPS_REASON_DNS_BLOCKED      → Domain blocked by DNS filter
IPS_REASON_FILE_MALICIOUS   → File hash matches known malware
IPS_REASON_URL_BLOCKED      → URL blocked by category filter
IPS_REASON_BOT_DETECTED     → Automated bot behavior detected
IPS_REASON_DDoS_ATTACK      → DDoS attack pattern detected
IPS_REASON_THREAT_FEED      → IOC matched threat intelligence feed
IPS_REASON_WAF_VIOLATION    → Web application firewall rule violated
IPS_REASON_SANDBOX_MALICIOUS → Sandbox analysis found malware
IPS_REASON_API_VIOLATION    → API protection rule violated
```

## Performance Characteristics

| Metric | Target | Notes |
|--------|--------|-------|
| Enforcement latency | < 20µs | Per packet, single core |
| Max connections | 100,000 | Configurable |
| Max blocklist entries | 50,000 | Configurable |
| Max quarantine entries | 10,000 | Configurable |
| Rate limit granularity | Per-IP, 1s window | Configurable |
| Fail-closed enforcement | Immediate | No grace period on component failure |

## Relationship with IDS

```
IDS (Detection)                        IPS (Prevention)
─────────────                          ─────────────
Passive, read-only                     Inline, can modify
Fail-open (traffic flows on error)     Fail-closed (traffic blocked on error)
Alerts → audit/log                     Actions → block/drop/reset
No packet modification                 Can drop/reset/throttle packets

Integration: IDS alert → IPS policy rule → automatic prevention
```

## Performance Optimizations

| Optimization | Description |
|--------------|-------------|
| Zero-copy packet capture | Avoid copying packet data between kernel and userspace |
| Connection state caching | Hot connections kept in fast lookup cache |
| Rule compilation | Rules compiled into efficient match structures (Aho-Corasick, etc.) |
| Parallel enforcement | Multi-threaded enforcement for high-throughput paths |
| Evaluation cache | Cache recent enforcement decisions to avoid recomputation |
| Batch processing | Process packets in batches for cache efficiency |
