# waf — Design

## Goals

1. **Application-layer protection** — Inspects HTTP/HTTPS traffic for SQL injection,
   XSS, CSRF, command injection, file inclusion, deserialization, bot traffic,
   API abuse, and more.
2. **Fail closed** — If waf cannot verify a request, it is blocked.
3. **Default-deny** — No traffic allowed unless an explicit rule permits it.
4. **Composable with ips** — waf adds application-layer enforcement on top of
   ips network-layer enforcement.
5. **Stateful enforcement** — Session tracking enables context-aware decisions.
6. **Audit every enforcement** — Every waf decision logged through usrauth/audit.

## Non-Goals

- Network-layer filtering — that is `security/ips/`.
- User-space execution — kernel-only subsystem.
- Long-term alert storage — events forwarded to SIEM; local storage bounded.

## Data Structures (Planned)

All mutable state in `.bss`, zero-initialized on load.

### waf_state_base_t (per-component)
```
+---------------------+  <---
| magic: resd 1       |      WAF_STATE_MAGIC for validation
+---------------------+
| version: resd 1     |      component version
+---------------------+
| refcount: resd 1    |      reference count
+---------------------+
| spinlock: resq 1    |      SMP spinlock
+---------------------+
| enabled: resb 1     |      component enabled flag
+---------------------+
| pad: resb 7         |      alignment
+---------------------+
| init_ns: resq 1     |      initialization timestamp
+---------------------+
| stats_requests: resq 1|   total requests inspected
+---------------------+
| stats_blocks: resq 1 |   total requests blocked
+---------------------+
| stats_challenges: resq 1|   total challenges issued
+---------------------+
| stats_logs: resq 1   |   total log entries
+---------------------+  <---
```

### waf_request_ctx_t (inspection input)
```
+---------------------+  <---
| timestamp_ns: resq 1|      request timestamp
+---------------------+
| src_ip: resd 1      |      IPv4 source address
+---------------------+
| dst_ip: resd 1      |      IPv4 destination address
+---------------------+
| src_port: resd 1    |
+---------------------+
| dst_port: resd 1    |
+---------------------+
| method: resd 1      |      WAF_METHOD_*
+---------------------+
| url: resq 1         |      NUL-terminated URL
+---------------------+
| url_len: resd 1     |
+---------------------+
| host: resq 1        |      NUL-terminated host
+---------------------+
| host_len: resd 1    |
+---------------------+
| user_agent: resq 1  |      NUL-terminated User-Agent
+---------------------+
| user_agent_len: resd 1|
+---------------------+
| content_type: resq 1|      NUL-terminated content type
+---------------------+
| content_len: resd 1 |      content body length
+---------------------+
| body: resq 1        |      request body pointer
+---------------------+
| body_len: resd 1    |      request body length
+---------------------+
| headers_count: resd 1|     number of headers
+---------------------+
| headers_ptr: resq 1 |      pointer to header name/value pairs
+---------------------+
| session_id: resq 1  |      associated session ID
+---------------------+
| session_ptr: resq 1 |      session context pointer
+---------------------+
| session_state: resd 1|     session state
+---------------------+
| session_ttl: resq 1 |      session TTL
+---------------------+
| api_key: resq 1     |      NUL-terminated API key
+---------------------+
| api_key_len: resd 1 |
+---------------------+
| session_flags: resd 1|     session flags
+---------------------+  <---
```

### waf_rule_t (detection rule)
```
+---------------------+  <---
| rule_id: resq 1     |      unique rule identifier
+---------------------+
| rule_name: resb 128 |      NUL-terminated rule name
+---------------------+
| rule_type: resd 1   |      WAF_ATTACK_*
+---------------------+
| severity: resd 1    |      WAF_SEV_*
+---------------------+
| action: resd 1      |      WAF_ACTION_*
+---------------------+
| enabled: resb 1
+---------------------+
| pad: resb 3
+---------------------+
| pattern_ptr: resq 1 |      detection pattern
+---------------------+
| pattern_len: resd 1 |
+---------------------+
| location: resd 1    |      where to inspect (URL, body, header, etc.)
+---------------------+
| hit_count: resq 1   |      hit count
+---------------------+
| next: resq 1        |      linked list
+---------------------+  <---
```

### waf_match_t (detection result)
```
+---------------------+  <---
| rule_id: resq 1     |      matched rule ID
+---------------------+
| attack_type: resd 1 |      WAF_ATTACK_*
+---------------------+
| severity: resd 1    |      WAF_SEV_*
+---------------------+
| matched_text: resq 1|      pointer to matched text
+---------------------+
| matched_len: resd 1 |
+---------------------+
| location: resd 1    |      where match occurred
+---------------------+
| confidence: resd 1  |      0-100 confidence score
+---------------------+
| next: resq 1        |      linked list
+---------------------+  <---
```

## State Machines

### 1. waf Subsystem State Machine

```
    ┌────────────────┐
    │  UNINITIALIZED │
    └───────┬────────┘
            │ waf_init()
            ▼
    ┌────────────────┐      waf_shutdown()      ┌────────────────┐
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
     ▼ request arrives
┌─────────────────┐
│  INSPECTING     │────┐
└─────────┬─────────┘    │
          │              │
          ▼              │ error/exception
┌─────────────────┐      │
│  ACTION RETURN  │──────┘
└─────────────────┘
```

### 2. Request Inspection State Machine

```
    ┌─────────────────┐
    │   REQUEST       │──────────────┐
    │   RECEIVED      │              │
    └─────────┬───────┘              │
              │                      │ waf parse failure
              ▼                      ▼
    ┌─────────────────┐   ┌─────────────────┐
    │  HTTP_PARSE     │   │  ACTION_BLOCK   │────┐
    │  (parser)       │   │  (waf blocked)  │    │
    └─────────┬───────┘   └─────────────────┘    │
              │ parse success                      │
              ▼                                    │
    ┌─────────────────┐                            │
    │  RULE_ENGINE    │────────────────────────────┘
    │  (rule match)   │
    └─────────┬───────┘
              │ match found
              ▼
    ┌─────────────────┐
    │  ACTION_BLOCK   │──────────────┐
    │                 │              │
    │  no match       │              │
    └─────────┬───────┘              ▼
              │                      ┌─────────────────┐
              ▼                      │  ACTION_ALLOW   │
    ┌─────────────────┐              └─────────────────┘
    │  DETECTORS      │──────────────┐
    │  (sqli/xss/etc) │              │ threat detected
    └─────────┬───────┘              ▼
              │ clean              ┌─────────────────┐
              ▼                      │  ACTION_ALLOW   │
    ┌─────────────────┐              └─────────────────┘
    │  ACTION_RETURN  │──────────────┐
    └─────────────────┘              │
                                     │
                               Caller receives action + attack_type + rule_id
```

## Detection Modules

| Module | Detection Method | Detects |
|--------|-----------------|---------|
| waf_sqli | Signature + heuristic | SQL injection: UNION SELECT, DROP TABLE, OR 1=1, etc. |
| waf_xss | Signature + heuristic | Cross-site scripting: <script>, onerror, javascript:, eval() |
| waf_csrf | Token validation + Referer check | Missing/invalid CSRF token |
| waf_fim | Path traversal pattern | ../ traversal, include() attacks, wrapper abuse |
| waf_cmd | Shell metacharacter detection | ; | & ` $( ) shell metacharacters |
| waf_deser | Serialization pattern detection | Java serialize, PHP unserialize, Python pickle |
| waf_api | Token validation + rate limiting | API key validation, rate limiting |
| waf_rate | Rate limit counters | IP-based rate limiting |
| waf_bot | User-Agent + behavioral heuristics | Scrapers, crawlers, automated tools |
| waf_session | Session tracking + fixation detection | Session hijacking, fixation |
| waf_geoip | IP-to-country mapping | Blocked countries/regions |
| waf_rulec | Rule compilation | Custom rule compilation into match structures |
| waf_siem | SIEM export | Alert export to SIEM in CEF/LEEF/JSON/SYSLOG |
| waf_stats | Statistics collection | Request/block/challenge counts |

## Deny Reason Attribution

Every DENY action carries a reason code:

```
WAF_REASON_SQLI             → SQL injection pattern detected
WAF_REASON_XSS              → Cross-site scripting detected
WAF_REASON_CSRF             → CSRF token missing/invalid
WAF_REASON_FILE_INCLUSION   → File inclusion attempt detected
WAF_REASON_CMD_INJECTION    → Command injection detected
WAF_REASON_DESERIALIZATION  → Insecure deserialization detected
WAF_REASON_BOT              → Automated bot detected
WAF_REASON_GEOIP_BLOCKED    → Source country blocked
WAF_REASON_POLICY_VIOLATION → Custom rule violation
WAF_REASON_RATE_LIMIT       → Rate limit exceeded
```

## Performance Characteristics

| Metric | Target | Notes |
|--------|--------|-------|
| Request inspection latency | < 50µs | Per request, single core |
| Max rules | 50,000 | Configurable |
| Max blocked IPs | 50,000 | Configurable |
| Max sessions | 100,000 | Configurable |
| Rate limit granularity | Per-IP, per-second | Configurable |
| Fail-closed enforcement | Immediate | No grace period on component failure |

## Relationship with IDS and IPS

```
IDS (Detection)          IPS (Network Prevention)     WAF (Application Prevention)
─────────────              ───────────────             ───────────────
Passive, read-only         Inline, network layer       Inline, application layer
Fail-open                  Fail-closed                 Fail-closed
Alerts → audit/log         Block/drop/reset            Block/challenge/redirect
No packet modification     Can modify packets          Can modify HTTP requests

Integration: IDS alert → waf rule → waf blocks request
             IDS alert → ips policy rule → ips blocks network traffic
```

## Performance Optimizations

| Optimization | Description |
|--------------|-------------|
| Rule compilation | Rules compiled into efficient match structures (Aho-Corasick) |
| Request caching | Frequent request patterns cached for fast rejection |
| Parallel inspection | Multi-threaded inspection for high-throughput paths |
| Evaluation cache | Cache recent request decisions to avoid recomputation |
