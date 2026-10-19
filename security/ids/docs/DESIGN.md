# ids — Design

## Goals

1. **Detection only** — IDS observes and reports. It never blocks, drops, or modifies traffic (that is IPS's domain).
2. **Fail open** — If IDS components fail, traffic flows unimpeded. Availability takes precedence over blocking.
3. **Comprehensive visibility** — Network (L2-L7), host (syscalls), and application-layer events are all inspected.
4. **Audit every alert** — Every detection emits an immutable audit record through `usrauth/audit`.
5. **Composable pipeline** — Components are loosely coupled; new detection modules can be added without rewriting the pipeline.

## Non-Goals

- Blocking or dropping traffic — that is `security/ips/`.
- Active response (shunning, session termination) — that is IPS + SOAR.
- User-space execution — kernel-only subsystem.
- Long-term alert storage — alerts are forwarded to SIEM; local storage is a bounded ring buffer.

## Data Structures (Planned)

All mutable state resides in `.bss`, zero-initialized on load.

### ids_state_base_t (per-component)

```
+---------------------+  <---
| magic: resd 1       |      IDS_STATE_MAGIC for validation
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
| stats_alerts: resq 1 |     total alerts generated
+---------------------+
| stats_drops: resq 1  |     total packets dropped (error)
+---------------------+  <---
```

### ids_packet_ctx_t (inspection input)

```
+---------------------+  <---
| timestamp_ns: resq 1|      packet capture timestamp
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
| payload_ptr: resq 1 |      pointer to packet payload
+---------------------+
| payload_len: resd 1 |      payload length
+---------------------+
| ingress_iface: resd1|      interface index
+---------------------+
| flags: resd 1       |      IDS_PKT_* flags
+---------------------+  <---
```

### ids_stream_t (TCP reassembly)

```
+---------------------+  <---
| stream_id: resq 1   |      unique stream identifier
+---------------------+
| src_ip/dst_ip: resd1|      5-tuple endpoints
| src_port/dst_port:resd1|
+---------------------+
| state: resd 1       |      IDS_STREAM_* (CLOSED, SYN_SENT, ESTABLISHED, ...)
+---------------------+
| seq_offset: resq 1  |      reassembly sequence offset
+---------------------+
| reasm_buf_ptr: resq1|      reassembly buffer pointer
+---------------------+
| reasm_buf_len: resd1|      current reassembled length
+---------------------+
| last_seen_ns: resq 1|      last packet timestamp
+---------------------+
| bytes_seen: resq 1  |      total bytes in stream
+---------------------+
| next: resq 1        |      linked list
+---------------------+  <---
```

### ids_rule_t (detection rule)

```
+---------------------+  <---
| rule_id: resq 1     |      unique rule identifier
+---------------------+
| rule_name: resb 128 |      NUL-terminated rule name
+---------------------+
| rule_type: resd 1   |      IDS_RULE_* (signature, anomaly, ...)
+---------------------+
| content_ptr: resq 1 |      pattern to match
+---------------------+
| severity: resd 1    |      IDS_SEV_*
+---------------------+
| hit_count: resq 1   |      times rule has matched
+---------------------+
| next: resq 1        |      linked list
+---------------------+  <---
```

### ids_alert_t (alert record)

```
+---------------------+  <---
| alert_id: resq 1    |      unique alert identifier
+---------------------+
| timestamp_ns: resq 1|      alert generation time
+---------------------+
| severity: resd 1    |      IDS_SEV_*
+---------------------+
| reason_code: resd 1 |      IDS_REASON_*
+---------------------+
| state: resd 1       |      IDS_ALERT_* (NEW, ACKED, ...)
+---------------------+
| description_ptr: resq1|     NUL-terminated description
+---------------------+
| next: resq 1        |      linked list
+---------------------+  <---
```

## State Machines

### 1. IDS Subsystem State Machine

```
    ┌────────────────┐
    │  UNINITIALIZED │
    └───────┬────────┘
            │ ids_init()
            ▼
    ┌────────────────┐      ids_shutdown()      ┌────────────────┐
    │   INITIALIZED  │ ───────────────────────► │   SHUTDOWN   │
    └───────┬────────┘                        └────────────────┘
            │
     ┌──────┴──────┐
     │             │
     ▼             ▼
┌─────────┐   ┌─────────────┐
│ ENABLED │   │   DISABLED  │  ← fail-open default
└────┬────┘   └─────────────┘
     │
     ▼ packet arrives
┌─────────────────┐
│  INSPECTING     │────┐
└─────────┬─────────┘    │
          │              │
          ▼              │ error/exception
┌─────────────────┐      │
│  VERDICT RETURN │──────┘
└─────────────────┘
```

**State transitions:**

| From → To | Trigger | Condition |
|-----------|---------|-----------|
| UNINITIALIZED → INITIALIZED | `ids_init()` | Returns 0 |
| INITIALIZED → ENABLED | `ids_status()` | Component ready |
| INITIALIZED → SHUTDOWN | `ids_shutdown()` | Teardown |
| ENABLED → DISABLED | Admin action | Explicit disable |
| ENABLED → INSPECTING | Packet arrives | `ids_inspect_packet()` called |
| INSPECTING → ENABLED | Verdict returned | CLEAN / SUSPICIOUS / THREAT / ERROR |
| INSPECTING → SHUTDOWN | Critical failure | Component fault |

### 2. Alert State Machine

```
    ┌─────────────────┐
    │     NEW         │──────────────────┐
    └───────┬─────────┘                  │
            │ acknowledged               │ auto-expire (TTL)
            ▼                            ▼
    ┌─────────────────┐   ┌─────────────────────┐
    │  ACKNOWLEDGED   │◀──│   RESOLVED          │
    │   (in review)   │   └─────────────────────┘
    └───────┬─────────┘
            │ investigated
            ▼
    ┌─────────────────┐
    │ INVESTIGATING   │
    └───────┬─────────┘
            │ resolved / false positive
            ▼
    ┌─────────────────┐
    │   RESOLVED      │──────────────────┐
    │  FALSE_POSITIVE │                  │
    └─────────────────┘                  │
                                         │ auto-expire (TTL)
                                         ▼
                                    ┌──────────┐
                                    │ ARCHIVED │
                                    └──────────┘
```

**Alert events:**

| Event | From → To | Action |
|-------|-----------|--------|
| `ids_alert_emit()` | — → NEW | Allocate alert ID, insert into list |
| analyst acknowledges | NEW → ACKNOWLEDGED | Mark state, record auditor |
| analyst investigates | ACKNOWLEDGED → INVESTIGATING | Start investigation timer |
| investigation complete | INVESTIGATING → RESOLVED/FALSE_POSITIVE | Record resolution |
| TTL exceeded | any → ARCHIVED | Move to cold storage |

### 3. Packet Inspection State Machine

```
    ┌─────────────────┐
    │   PACKET        │──────────────┐
    │   RECEIVED      │              │
    └─────────┬───────┘              │
              │                      │ sensor capture fail
              ▼                      ▼
    ┌─────────────────┐   ┌─────────────────┐
    │  SENSOR_CAPTURE │   │  VERDICT_ERROR  │────┐
    └─────────┬───────┘   └─────────────────┘    │
              │ success                          │
              ▼                                  │
    ┌─────────────────┐                          │
    │  REASSEMBLER    │──────────────────────────┘
    │  (stream mgmt)  │
    └─────────┬───────┘
              │ complete stream ready
              ▼
    ┌─────────────────┐
    │   ANALYZER      │──────────────┐
    │  (protocol)     │              │ unknown protocol
    └─────────┬───────┘              ▼
              │ continue             ┌─────────────────┐
              ▼                      │  VERDICT_CLEAN  │
    ┌─────────────────┐              └─────────────────┘
    │    RULES        │──────────────┐
    │  (signature)    │              │ no match
    └─────────┬───────┘              ▼
              │ match                ┌─────────────────┐
              ▼                      │  VERDICT_CLEAN  │
    ┌─────────────────┐              └─────────────────┘
    │   DETECTOR      │──────────────┐
    │  (anomaly)      │              │ score < threshold
    └─────────┬───────┘              ▼
              │ score >= threshold   ┌─────────────────┐
              ▼                      │ VERDICT_SUSPICIOUS│
    ┌─────────────────┐              └─────────────────┘
    │   CORRELATOR    │──────────────┐
    │  (threat score) │              │
    └─────────┬───────┘              ▼
              │                      ┌─────────────────┐
              ▼                      │ VERDICT_THREAT  │
    ┌─────────────────┐              └─────────────────┘
    │    ALERT        │──────────────┐
    │   (emit)        │              │
    └─────────┬───────┘              ▼
              │                      ┌─────────────────┐
              ▼                      │ VERDICT_RETURN  │
    ┌─────────────────┐              └─────────────────┘
    │    SIEM         │──────────────┐
    │   (export)      │              │
    └─────────┬───────┘              ▼
              │                      ┌─────────────────┐
              ▼                      │   STATS         │
    ┌─────────────────┐              │   (record)      │
    │   STATS         │──────────────┘
    │   (record)      │
    └─────────────────┘
              │
              ▼
    ┌─────────────────┐
    │ VERDICT_RETURN  │──────────────┐
    └─────────────────┘              │
                                     ▼
                              Caller receives verdict + reason
```

## Detection Modules

| Module | Detection Method | Trigger Condition |
|--------|-----------------|-------------------|
| Signature | Byte-pattern matching | Payload matches known bad pattern |
| Anomaly | Statistical deviation | Traffic deviates from baseline > threshold |
| Protocol | RFC compliance check | Malformed protocol headers/payloads |
| Blacklist | IP/domain reputation | Source or destination in blocklist |
| Behavioral | Baseline deviation | Unusual volume, timing, or pattern |

## Deny Reason Attribution

Every DENY/SUSPICIOUS verdict carries a reason code so audit logs explain WHY:

```
IDS_REASON_SIGNATURE_MATCH   → Known bad pattern found in payload
IDS_REASON_ANOMALY_THRESHOLD → Traffic volume/timing deviates from baseline
IDS_REASON_PROTOCOL_VIOLATION → Malformed protocol headers detected
IDS_REASON_BLACKLISTED_IP     → Source or destination IP is blocked
IDS_REASON_SCAN_DETECTED      → Port scan pattern (N ports in T seconds)
IDS_REASON_BRUTE_FORCE        → Repeated failed authentication attempts
IDS_REASON_DATA_EXFILTRATION  → Unusual outbound data volume
IDS_REASON_MALWARE_C2         → Periodic beaconing to external C2
IDS_REASON_POLICY_VIOLATION   → Organizational policy breach (e.g., PII outbound)
```

## Performance Characteristics

| Metric | Target | Notes |
|--------|--------|-------|
| Packet inspection latency | < 50µs | Per packet, single core |
| Alert deduplication window | 300s | Configurable |
| Max concurrent streams | 10,000 | Configurable |
| Max rules | 100,000 | Configurable |
| Alert TTL | 7 days | Configurable |
| Stats sample interval | 60s | Configurable |
