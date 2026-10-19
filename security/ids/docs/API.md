# ids — API Reference

## Overview

All symbols follow the NASM x86-64 calling convention:
- Callee-saved registers (`rbx`, `rbp`, `r12`–`r15`) preserved across calls.
- Return convention: `rax = 0` on success, negative errno-style on failure.
- `IDS_VERDICT_*` for inspection verdicts, `IDS_REASON_*` for denial/alert reasons.
- All pointers are 64-bit virtual addresses.

---

## Symbol Index

### ids (main dispatcher)

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `ids_init` | none | rax = status | Initialize IDS |
| `ids_shutdown` | none | rax = status | Shut down IDS |
| `ids_status` | none | rax = status | Current subsystem status |
| `ids_version` | none | rax = ptr | NUL-terminated version string |
| `ids_inspect_packet` | rdi = packet_ctx* | rax = verdict, rbx = reason | Inspect a single packet through full pipeline |
| `ids_get_stats` | rdi = stats buffer* | rax = status | Copy current statistics snapshot |

### ids_sensor

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `ids_sensor_init` | none | rax = status | Initialize sensor |
| `ids_sensor_shutdown` | none | rax = status | Shut down sensor |
| `ids_sensor_status` | none | rax = status | Current status |
| `ids_sensor_version` | none | rax = ptr | Version string |
| `ids_sensor_capture` | rdi = packet_ctx* | rax = 0 if packet captured | Capture next packet from interface |

### ids_reassembler

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `ids_reassembler_init` | none | rax = status | Initialize reassembler |
| `ids_reassembler_shutdown` | none | rax = status | Shut down |
| `ids_reassembler_status` | none | rax = status | Current status |
| `ids_reassembler_version` | none | rax = ptr | Version string |
| `ids_reassembler_add_packet` | rdi = packet_ctx* | rax = stream_id or 0 or error | Add packet to TCP stream reassembly |

### ids_analyzer

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `ids_analyzer_init` | none | rax = status | Initialize analyzer |
| `ids_analyzer_shutdown` | none | rax = status | Shut down |
| `ids_analyzer_status` | none | rax = status | Current status |
| `ids_analyzer_version` | none | rax = ptr | Version string |
| `ids_analyzer_parse` | rdi=stream*, rsi=payload*, rdx=len | rax=status, rbx=protocol_id | Parse application-layer protocol |

### ids_rules

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `ids_rules_init` | none | rax = status | Initialize rules engine |
| `ids_rules_shutdown` | none | rax = status | Shut down |
| `ids_rules_status` | none | rax = status | Current status |
| `ids_rules_version` | none | rax = ptr | Version string |
| `ids_rules_load` | rdi=rules_src*, rsi=size | rax=rules_loaded_count | Load rules from file/memory |
| `ids_rules_match` | rdi=packet_ctx* | rax=rule_id, rbx=severity | Match packet against rule database |

### ids_detector

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `ids_detector_init` | none | rax = status | Initialize detector |
| `ids_detector_shutdown` | none | rax = status | Shut down |
| `ids_detector_status` | none | rax = status | Current status |
| `ids_detector_version` | none | rax = ptr | Version string |
| `ids_detector_evaluate` | rdi=packet_ctx* | rax=score(0-100), rbx=reason | Evaluate packet for anomalies |

### ids_alert

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `ids_alert_init` | none | rax = status | Initialize alert engine |
| `ids_alert_shutdown` | none | rax = status | Shut down |
| `ids_alert_status` | none | rax = status | Current status |
| `ids_alert_version` | none | rax = ptr | Version string |
| `ids_alert_emit` | rdi=severity, rsi=reason, ... | rax=alert_id | Emit a new alert |
| `ids_alert_acknowledge` | rdi=alert_id, rsi=new_state | rax=status | Acknowledge/resolve alert |

### ids_correlator

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `ids_correlator_init` | none | rax = status | Initialize correlator |
| `ids_correlator_shutdown` | none | rax = status | Shut down |
| `ids_correlator_status` | none | rax = status | Current status |
| `ids_correlator_version` | none | rax = ptr | Version string |
| `ids_correlator_update` | rdi=subject_ip, rsi=context* | rax=threat_score, rbx=corr_id | Update threat correlation |

### ids_siem

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `ids_siem_init` | none | rax = status | Initialize SIEM exporter |
| `ids_siem_shutdown` | none | rax = status | Shut down |
| `ids_siem_status` | none | rax = status | Current status |
| `ids_siem_version` | none | rax = ptr | Version string |
| `ids_siem_export` | rdi=alert* | rax=status | Export alert to SIEM |

### ids_stats

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `ids_stats_init` | none | rax = status | Initialize stats engine |
| `ids_stats_shutdown` | none | rax = status | Shut down |
| `ids_stats_status` | none | rax = status | Current status |
| `ids_stats_version` | none | rax = ptr | Version string |
| `ids_stats_record` | rdi=packet_ctx*, rsi=verdict, rdx=reason | rax=status | Record inspection metrics |

---

## Verdict Codes

| Code | Symbol | Meaning |
|------|--------|---------|
| 0 | `IDS_VERDICT_CLEAN` | No threat detected |
| 1 | `IDS_VERDICT_SUSPICIOUS` | Suspicious activity, watch |
| 2 | `IDS_VERDICT_THREAT` | Confirmed threat, alert |
| -1 | `IDS_VERDICT_ERROR` | Inspection error |

---

## Alert Reason Codes

| Code | Symbol | Meaning |
|------|--------|---------|
| 0 | `IDS_REASON_NONE` | No threat |
| -1 | `IDS_REASON_SIGNATURE_MATCH` | Signature rule matched |
| -2 | `IDS_REASON_ANOMALY_THRESHOLD` | Statistical anomaly exceeded |
| -3 | `IDS_REASON_PROTOCOL_VIOLATION` | Malformed protocol traffic |
| -4 | `IDS_REASON_BLACKLISTED_IP` | Source/dest in blocklist |
| -5 | `IDS_REASON_SCAN_DETECTED` | Port/network scan pattern |
| -6 | `IDS_REASON_BRUTE_FORCE` | Authentication brute force |
| -7 | `IDS_REASON_DATA_EXFILTRATION` | Potential data exfiltration |
| -8 | `IDS_REASON_MALWARE_C2` | Command & control beacon |
| -9 | `IDS_REASON_POLICY_VIOLATION` | Organizational policy breach |
| -10 | `IDS_REASON_INSPECTOR_ERROR` | Inspection subsystem error |

---

## Severity Levels

| Code | Symbol | Meaning |
|------|--------|---------|
| 0 | `IDS_SEV_INFO` | Informational |
| 1 | `IDS_SEV_LOW` | Low severity |
| 2 | `IDS_SEV_MEDIUM` | Medium severity |
| 3 | `IDS_SEV_HIGH` | High severity |
| 4 | `IDS_SEV_CRITICAL` | Critical severity |

---

## Alert States

| Code | Symbol | Meaning |
|------|--------|---------|
| 0 | `IDS_ALERT_NEW` | New alert, unreviewed |
| 1 | `IDS_ALERT_ACKNOWLEDGED` | Acknowledged by analyst |
| 2 | `IDS_ALERT_INVESTIGATING` | Under investigation |
| 3 | `IDS_ALERT_RESOLVED` | Resolved |
| 4 | `IDS_ALERT_FALSE_POSITIVE` | Determined false positive |

---

## Stream States

| Code | Symbol | Meaning |
|------|--------|---------|
| 0 | `IDS_STREAM_CLOSED` | Stream closed |
| 1 | `IDS_STREAM_SYN_SENT` | SYN sent, waiting |
| 2 | `IDS_STREAM_ESTABLISHED` | Stream established |
| 3 | `IDS_STREAM_FIN_WAIT` | FIN wait state |
| 4 | `IDS_STREAM_CLOSE_WAIT` | Close wait state |
| 5 | `IDS_STREAM_ERROR` | Stream error |

---

## Packet Flags

| Flag | Symbol | Meaning |
|------|--------|---------|
| 1<<0 | `IDS_PKT_FRAGMENT` | IP fragment |
| 1<<1 | `IDS_PKT_RETRANSMIT` | Suspected TCP retransmit |
| 1<<2 | `IDS_PKT_ENCRYPTED` | TLS/encrypted payload |
| 1<<3 | `IDS_PKT_INTERNAL` | Internal network source |

---

## Rule Types

| Code | Symbol | Meaning |
|------|--------|---------|
| 0 | `IDS_RULE_SIGNATURE` | Byte-pattern signature |
| 1 | `IDS_RULE_ANOMALY` | Statistical anomaly |
| 2 | `IDS_RULE_PROTOCOL` | Protocol violation |
| 3 | `IDS_RULE_BLACKLIST` | IP/domain blacklist |
| 4 | `IDS_RULE_BEHAVIORAL` | Behavioral heuristic |

---

## Build

```bash
make -C security/ids all
make -C security/ids test
```
