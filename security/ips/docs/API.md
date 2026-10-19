# ips — API Reference

## Overview

All symbols follow the NASM x86-64 calling convention:
- Callee-saved registers (`rbx`, `rbp`, `r12`–`r15`) preserved across calls.
- Return convention: `rax = action` on success, negative errno-style on failure.
- `IPS_ACTION_*` for enforcement actions, `IPS_REASON_*` for denial reasons.
- All pointers are 64-bit virtual addresses.

---

## Symbol Index

### ips (main dispatcher)

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `ips_init` | none | rax = status | Initialize IPS |
| `ips_shutdown` | none | rax = status | Shut down IPS |
| `ips_status` | none | rax = status | Current subsystem status |
| `ips_version` | none | rax = ptr | NUL-terminated version string |
| `ips_enforce` | rdi = enforce_ctx* | rax = action, rbx = reason, rcx = duration_ms | Enforce inline access decision |
| `ips_get_stats` | rdi = stats buffer* | rax = status | Copy current statistics snapshot |

### ips_inspector

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `ips_inspector_init` | none | rax = status | Initialize inspector |
| `ips_inspector_shutdown` | none | rax = status | Shut down inspector |
| `ips_inspector_status` | none | rax = status | Current status |
| `ips_inspector_version` | none | rax = ptr | Version string |
| `ips_inspector_inspect` | rdi = enforce_ctx* | rax = result, rbx = action, rcx = reason | Inspect packet inline |

### ips_enforcer

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `ips_enforcer_init` | none | rax = status | Initialize enforcer |
| `ips_enforcer_shutdown` | none | rax = status | Shut down enforcer |
| `ips_enforcer_status` | none | rax = status | Current status |
| `ips_enforcer_version` | none | rax = ptr | Version string |
| `ips_enforcer_apply_action` | rdi = action, rsi = ctx*, rdx = duration_ms | rax = status | Apply enforcement action |

### ips_policy

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `ips_policy_init` | none | rax = status | Initialize policy engine |
| `ips_policy_shutdown` | none | rax = status | Shut down policy engine |
| `ips_policy_status` | none | rax = status | Current status |
| `ips_policy_version` | none | rax = ptr | Version string |
| `ips_policy_load` | rdi = rules_src*, rsi = size | rax = rules_loaded_count | Load rules from file/memory |
| `ips_policy_evaluate` | rdi = enforce_ctx* | rax = action, rbx = reason | Evaluate request against policies |

### ips_bypass

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `ips_bypass_init` | none | rax = status | Initialize bypass |
| `ips_bypass_shutdown` | none | rax = status | Shut down bypass |
| `ips_bypass_status` | none | rax = status | Current status |
| `ips_bypass_version` | none | rax = ptr | Version string |
| `ips_bypass_check` | rdi = enforce_ctx* | rax = 1 (bypass) / 0 (enforce) | Check if traffic bypasses enforcement |
| `ips_bypass_set_fail_mode` | rdi = fail_mode | rax = status | Set fail-closed / fail-open mode |

### ips_rate_limiter

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `ips_rate_limiter_init` | none | rax = status | Initialize rate limiter |
| `ips_rate_limiter_shutdown` | none | rax = status | Shut down rate limiter |
| `ips_rate_limiter_status` | none | rax = status | Current status |
| `ips_rate_limiter_version` | none | rax = ptr | Version string |
| `ips_rate_limiter_check` | rdi = src_ip | rax = 0 (ok) / neg (limited), rbx = retry_after_ms | Check rate limit per IP |

### ips_connection_tracker

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `ips_connection_tracker_init` | none | rax = status | Initialize connection tracker |
| `ips_connection_tracker_shutdown` | none | rax = status | Shut down connection tracker |
| `ips_connection_tracker_status` | none | rax = status | Current status |
| `ips_connection_tracker_version` | none | rax = ptr | Version string |
| `ips_connection_tracker_track` | rdi = enforce_ctx*, rsi = new_state | rax = conn_id | Track connection state transition |

### ips_quarantine

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `ips_quarantine_init` | none | rax = status | Initialize quarantine |
| `ips_quarantine_shutdown` | none | rax = status | Shut down quarantine |
| `ips_quarantine_status` | none | rax = status | Current status |
| `ips_quarantine_version` | none | rax = ptr | Version string |
| `ips_quarantine_isolate` | rdi = ip, rsi = reason_code | rax = status | Isolate endpoint in quarantine |
| `ips_quarantine_release` | rdi = ip | rax = status | Release endpoint from quarantine |

### ips_blocklist

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `ips_blocklist_init` | none | rax = status | Initialize blocklist |
| `ips_blocklist_shutdown` | none | rax = status | Shut down blocklist |
| `ips_blocklist_status` | none | rax = status | Current status |
| `ips_blocklist_version` | none | rax = ptr | Version string |
| `ips_blocklist_add` | rdi = ip, rsi = reason, rdx = expires_ns | rax = status | Add IP to blocklist |
| `ips_blocklist_remove` | rdi = ip | rax = status | Remove IP from blocklist |
| `ips_blocklist_check` | rdi = ip | rax = 0 (not blocked) / 1 (blocked), rbx = reason | Check if IP is blocked |

### ips_siem

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `ips_siem_init` | none | rax = status | Initialize SIEM exporter |
| `ips_siem_shutdown` | none | rax = status | Shut down SIEM exporter |
| `ips_siem_status` | none | rax = status | Current status |
| `ips_siem_version` | none | rax = ptr | Version string |
| `ips_siem_export` | rdi = enforce_result* | rax = status | Export enforcement event to SIEM |

### ips_stats

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `ips_stats_init` | none | rax = status | Initialize stats engine |
| `ips_stats_shutdown` | none | rax = status | Shut down stats engine |
| `ips_stats_status` | none | rax = status | Current status |
| `ips_stats_version` | none | rax = ptr | Version string |
| `ips_stats_record` | rdi = enforce_ctx*, rsi = action, rdx = reason_code | rax = status | Record enforcement metrics |

### ips_geoip

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `ips_geoip_init` | none | rax = status | Initialize GeoIP filter |
| `ips_geoip_shutdown` | none | rax = status | Shut down GeoIP filter |
| `ips_geoip_status` | none | rax = status | Current status |
| `ips_geoip_version` | none | rax = ptr | Version string |
| `ips_geoip_lookup` | rdi = IP address | rax = country_code, rbx = continent_code | Look up country for an IP |
| `ips_geoip_is_blocked` | rdi = country_code | rax = 1 (blocked) / 0 (allowed) | Check if country is blocked |

### ips_app_control

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `ips_app_control_init` | none | rax = status | Initialize application control |
| `ips_app_control_shutdown` | none | rax = status | Shut down application control |
| `ips_app_control_status` | none | rax = status | Current status |
| `ips_app_control_version` | none | rax = ptr | Version string |
| `ips_app_control_detect` | rdi = enforce_ctx* | rax = app_id, rbx = category_code | Detect application from traffic |
| `ips_app_control_is_allowed` | rdi = app_id | rax = 1 (allowed) / 0 (blocked) | Check if application is allowed |

### ips_tls_inspector

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `ips_tls_inspector_init` | none | rax = status | Initialize TLS inspector |
| `ips_tls_inspector_shutdown` | none | rax = status | Shut down TLS inspector |
| `ips_tls_inspector_status` | none | rax = status | Current status |
| `ips_tls_inspector_version` | none | rax = ptr | Version string |
| `ips_tls_inspector_inspect` | rdi = enforce_ctx* | rax = 0 (clean) / neg (violation), rbx = threat_score | Inspect TLS handshake |
| `ips_tls_inspector_check_fingerprint` | rdi = fingerprint*, rsi = len | rax = 1 (malicious) / 0 (good) / -1 (unknown), rbx = threat_score | Check TLS fingerprint against database |

### ips_dns_filter

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `ips_dns_filter_init` | none | rax = status | Initialize DNS filter |
| `ips_dns_filter_shutdown` | none | rax = status | Shut down DNS filter |
| `ips_dns_filter_status` | none | rax = status | Current status |
| `ips_dns_filter_version` | none | rax = ptr | Version string |
| `ips_dns_filter_check` | rdi = domain*, rsi = domain_len | rax = 1 (blocked) / 0 (allowed), rbx = category_code | Check if domain is blocked |
| `ips_dns_filter_block` | rdi = domain*, rsi = domain_len, rdx = category | rax = status | Block a domain |

### ips_file_analysis

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `ips_file_analysis_init` | none | rax = status | Initialize file analysis |
| `ips_file_analysis_shutdown` | none | rax = status | Shut down file analysis |
| `ips_file_analysis_status` | none | rax = status | Current status |
| `ips_file_analysis_version` | none | rax = ptr | Version string |
| `ips_file_analysis_check_hash` | rdi = SHA-256 hash* | rax = 1 (malicious) / 0 (clean) / -1 (unknown), rbx = threat_score | Check file hash reputation |
| `ips_file_analysis_send_sandbox` | rdi = file*, rsi = file_len | rax = sandbox_job_id | Submit file to sandbox for analysis |

### ips_url_filter

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `ips_url_filter_init` | none | rax = status | Initialize URL filter |
| `ips_url_filter_shutdown` | none | rax = status | Shut down URL filter |
| `ips_url_filter_status` | none | rax = status | Current status |
| `ips_url_filter_version` | none | rax = ptr | Version string |
| `ips_url_filter_check` | rdi = URL*, rsi = URL_len | rax = 1 (blocked) / 0 (allowed), rbx = category_code | Check if URL is blocked |
| `ips_url_filter_categorize` | rdi = URL*, rsi = URL_len | rax = category_code, rbx = threat_score | Get URL category without blocking |

### ips_bot_detector

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `ips_bot_detector_init` | none | rax = status | Initialize bot detector |
| `ips_bot_detector_shutdown` | none | rax = status | Shut down bot detector |
| `ips_bot_detector_status` | none | rax = status | Current status |
| `ips_bot_detector_version` | none | rax = ptr | Version string |
| `ips_bot_detector_check` | rdi = enforce_ctx* | rax = 1 (bot) / 0 (human), rbx = bot_score (0-100) | Check if traffic is from a bot |
| `ips_bot_detector_score` | rdi = src_ip | rax = bot_score (0-100), rbx = confidence (0-100) | Calculate bot probability score for an IP |

### ips_ddos_protector

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `ips_ddos_protector_init` | none | rax = status | Initialize DDoS protector |
| `ips_ddos_protector_shutdown` | none | rax = status | Shut down DDoS protector |
| `ips_ddos_protector_status` | none | rax = status | Current status |
| `ips_ddos_protector_version` | none | rax = ptr | Version string |
| `ips_ddos_protector_check` | rdi = enforce_ctx* | rax = 0 (ok) / neg (DDoS), rbx = attack_type | Check traffic against DDoS thresholds |
| `ips_ddos_protector_mitigate` | rdi = attack_type, rsi = src_ip (0 = all), rdx = duration_ms | rax = status | Apply DDoS mitigation |

### ips_threat_feed

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `ips_threat_feed_init` | none | rax = status | Initialize threat feed |
| `ips_threat_feed_shutdown` | none | rax = status | Shut down threat feed |
| `ips_threat_feed_status` | none | rax = status | Current status |
| `ips_threat_feed_version` | none | rax = ptr | Version string |
| `ips_threat_feed_update` | none | rax = new_IOCs_count | Update threat feeds from configured sources |
| `ips_threat_feed_check_ioc` | rdi = ioc_type (1=IP,2=domain,3=URL,4=hash), rsi = ioc_value* | rax = 1 (malicious) / 0 (clean) / -1 (unknown), rbx = threat_score (0-100), rcx = feed_source_id | Check indicator against threat feeds |

### ips_waf_engine

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `ips_waf_engine_init` | none | rax = status | Initialize WAF engine |
| `ips_waf_engine_shutdown` | none | rax = status | Shut down WAF engine |
| `ips_waf_engine_status` | none | rax = status | Current status |
| `ips_waf_engine_version` | none | rax = ptr | Version string |
| `ips_waf_engine_inspect` | rdi = enforce_ctx* | rax = 0 (clean) / neg (violation), rbx = threat_score (0-100), rcx = rule_id | Inspect HTTP request for web attacks |
| `ips_waf_engine_block` | rdi = IP, rsi = rule_id, rdx = duration_ms | rax = status | Block an IP via WAF |

### ips_packet_capture

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `ips_packet_capture_init` | none | rax = status | Initialize packet capture |
| `ips_packet_capture_shutdown` | none | rax = status | Shut down packet capture |
| `ips_packet_capture_status` | none | rax = status | Current status |
| `ips_packet_capture_version` | none | rax = ptr | Version string |
| `ips_packet_capture_start` | rdi = filter_expr*, rsi = filter_len, rdx = max_packets | rax = status | Start packet capture |
| `ips_packet_capture_stop` | none | rax = packets_captured | Stop packet capture |

### ips_ha_cluster

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `ips_ha_cluster_init` | none | rax = status | Initialize HA cluster |
| `ips_ha_cluster_shutdown` | none | rax = status | Shut down HA cluster |
| `ips_ha_cluster_status` | none | rax = status | Current status |
| `ips_ha_cluster_version` | none | rax = ptr | Version string |
| `ips_ha_cluster_failover` | rdi = target_node_id (0 = automatic) | rax = status | Trigger failover to another node |
| `ips_ha_cluster_sync` | rdi = target_node_id (0 = all) | rax = status | Synchronize configuration and state |

### ips_api_protection

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `ips_api_protection_init` | none | rax = status | Initialize API protection |
| `ips_api_protection_shutdown` | none | rax = status | Shut down API protection |
| `ips_api_protection_status` | none | rax = status | Current status |
| `ips_api_protection_version` | none | rax = ptr | Version string |
| `ips_api_protection_authenticate` | rdi = enforce_ctx* | rax = 0 (authenticated) / neg (failed), rbx = user_id | Authenticate API request |
| `ips_api_protection_rate_limit` | rdi = api_key*, rsi = key_len | rax = 0 (within limit) / neg (limited), rbx = retry_after_ms | Check API rate limit |

### ips_ml_anomaly

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `ips_ml_anomaly_init` | none | rax = status | Initialize ML anomaly detection |
| `ips_ml_anomaly_shutdown` | none | rax = status | Shut down ML anomaly detection |
| `ips_ml_anomaly_status` | none | rax = status | Current status |
| `ips_ml_anomaly_version` | none | rax = ptr | Version string |
| `ips_ml_anomaly_score` | rdi = enforce_ctx* | rax = anomaly_score (0-100), rbx = confidence (0-100) | Score traffic for anomalies |
| `ips_ml_anomaly_train` | rdi = training_data*, rsi = data_len | rax = status | Train ML model on normal traffic |

---

## Enforcement Actions

| Code | Symbol | Meaning |
|------|--------|---------|
| 0 | `IPS_ACTION_ALLOW` | Permit traffic |
| 1 | `IPS_ACTION_DROP` | Silently drop packet |
| 2 | `IPS_ACTION_RESET` | Send TCP RST to both endpoints |
| 3 | `IPS_ACTION_THROTTLE` | Rate-limit, allow reduced bandwidth |
| 4 | `IPS_ACTION_QUARANTINE` | Isolate endpoint, redirect to quarantine |
| 5 | `IPS_ACTION_BLOCK` | Block endpoint for duration |
| 6 | `IPS_ACTION_REDIRECT` | Redirect to different destination |
| 7 | `IPS_ACTION_INSPECT_DEEP` | Send to deep packet inspection |
| 8 | `IPS_ACTION_SANDBOX` | Send file to sandbox for analysis |
| 9 | `IPS_ACTION_CHALLENGE` | CAPTCHA / challenge-response |

---

## Enforcement Verdicts

| Code | Symbol | Meaning |
|------|--------|---------|
| 0 | `IPS_VERDICT_ALLOW` | Traffic allowed |
| -1 | `IPS_VERDICT_DROP` | Packet dropped |
| -2 | `IPS_VERDICT_RESET` | Connection reset |
| -3 | `IPS_VERDICT_THROTTLE` | Traffic throttled |
| -4 | `IPS_VERDICT_QUARANTINE` | Endpoint quarantined |
| -5 | `IPS_VERDICT_BLOCK` | Endpoint blocked |
| -100 | `IPS_VERDICT_ERROR` | Enforcement error |

---

## Enforcement Reason Codes

| Code | Symbol | Meaning |
|------|--------|---------|
| 0 | `IPS_REASON_NONE` | No enforcement action |
| -1 | `IPS_REASON_BLACKLISTED_IP` | Source/dest in blocklist |
| -2 | `IPS_REASON_POLICY_VIOLATION` | Explicit policy deny |
| -3 | `IPS_REASON_RATE_LIMIT` | Rate limit exceeded |
| -4 | `IPS_REASON_IDS_ALERT` | Triggered by IDS detection |
| -5 | `IPS_REASON_PROTOCOL_VIOLATION` | Malformed protocol traffic |
| -6 | `IPS_REASON_QUARANTINED_HOST` | Endpoint is quarantined |
| -7 | `IPS_REASON_CONNECTION_LIMIT` | Connection count limit exceeded |
| -8 | `IPS_REASON_COMPONENT_DOWN` | Enforcement component unavailable |
| -9 | `IPS_REASON_INVALID_REQUEST` | Malformed enforcement request |
| -10 | `IPS_REASON_GEOIP_BLOCKED` | Country/region blocked |
| -11 | `IPS_REASON_APP_BLOCKED` | Application not allowed |
| -12 | `IPS_REASON_TLS_VIOLATION` | TLS certificate/fingerprint violation |
| -13 | `IPS_REASON_DNS_BLOCKED` | Domain blocked by DNS filter |
| -14 | `IPS_REASON_FILE_MALICIOUS` | File hash matches known malware |
| -15 | `IPS_REASON_URL_BLOCKED` | URL blocked by category filter |
| -16 | `IPS_REASON_BOT_DETECTED` | Automated bot behavior detected |
| -17 | `IPS_REASON_DDoS_ATTACK` | DDoS attack pattern detected |
| -18 | `IPS_REASON_THREAT_FEED` | IOC matched threat intelligence feed |
| -19 | `IPS_REASON_WAF_VIOLATION` | Web application firewall rule violated |
| -20 | `IPS_REASON_SANDBOX_MALICIOUS` | Sandbox analysis found malware |
| -21 | `IPS_REASON_API_VIOLATION` | API protection rule violated |

---

## Fail Modes

| Code | Symbol | Meaning |
|------|--------|---------|
| 0 | `IPS_FAIL_CLOSED` | Block on error (secure default) |
| 1 | `IPS_FAIL_OPEN` | Allow on error (HA paths only) |

---

## Connection States

| Code | Symbol | Meaning |
|------|--------|---------|
| 0 | `IPS_CONN_NEW` | New connection |
| 1 | `IPS_CONN_ESTABLISHED` | Connection established |
| 2 | `IPS_CONN_RELATED` | Related connection |
| 3 | `IPS_CONN_INVALID` | Invalid connection |

---

## Build

```bash
make -C security/ips all
make -C security/ips test
```
