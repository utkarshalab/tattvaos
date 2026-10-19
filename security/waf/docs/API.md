# waf — API Reference

## Overview

All symbols follow the NASM x86-64 calling convention:
- Callee-saved registers (`rbx`, `rbp`, `r12`–`r15`) preserved across calls.
- Return convention: `rax = action` on success, negative errno-style on failure.
- `WAF_ACTION_*` for enforcement actions, `WAF_REASON_*` for denial reasons.
- All pointers are 64-bit virtual addresses.

## Symbol Index

### waf (main dispatcher)

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `waf_init` | none | rax = status | Initialize WAF |
| `waf_shutdown` | none | rax = status | Shut down WAF |
| `waf_status` | none | rax = status | Current subsystem status |
| `waf_version` | none | rax = ptr | NUL-terminated version string |
| `waf_inspect` | rdi = request_ctx* | rax = action, rbx = attack_type, rcx = rule_id | Inspect HTTP request through full pipeline |
| `waf_get_stats` | rdi = stats buffer* | rax = status | Copy current statistics snapshot |

### waf_core

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `waf_core_init` | none | rax = status | Initialize WAF core |
| `waf_core_shutdown` | none | rax = status | Shut down core |
| `waf_core_status` | none | rax = status | Current status |
| `waf_core_version` | none | rax = ptr | Version string |

### waf_rule

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `waf_rule_init` | none | rax = status | Initialize rule engine |
| `waf_rule_shutdown` | none | rax = status | Shut down rule engine |
| `waf_rule_status` | none | rax = status | Current status |
| `waf_rule_version` | none | rax = ptr | Version string |
| `waf_rule_load` | rdi = rules_src*, rsi = size | rax = rules_loaded_count | Load rules from file/memory |
| `waf_rule_evaluate` | rdi = request_ctx* | rax = action, rbx = attack_type, rcx = rule_id | Evaluate request against rules |

### waf_http

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `waf_http_init` | none | rax = status | Initialize HTTP inspector |
| `waf_http_shutdown` | none | rax = status | Shut down HTTP inspector |
| `waf_http_status` | none | rax = status | Current status |
| `waf_http_version` | none | rax = ptr | Version string |
| `waf_http_parse` | rdi = request_ctx* | rax = status | Parse HTTP request |
| `waf_http_extract` | rdi = request_ctx* | rax = status | Extract request features |

### waf_sqli

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `waf_sqli_init` | none | rax = status | Initialize SQLi detector |
| `waf_sqli_shutdown` | none | rax = status | Shut down SQLi detector |
| `waf_sqli_status` | none | rax = status | Current status |
| `waf_sqli_version` | none | rax = ptr | Version string |
| `waf_sqli_detect` | rdi = request_ctx* | rax = 1 (detected) / 0 (clean), rbx = threat_score | Detect SQL injection |

### waf_xss

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `waf_xss_init` | none | rax = status | Initialize XSS detector |
| `waf_xss_shutdown` | none | rax = status | Shut down XSS detector |
| `waf_xss_status` | none | rax = status | Current status |
| `waf_xss_version` | none | rax = ptr | Version string |
| `waf_xss_detect` | rdi = request_ctx* | rax = 1 (detected) / 0 (clean), rbx = threat_score | Detect XSS |

### waf_csrf

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `waf_csrf_init` | none | rax = status | Initialize CSRF protector |
| `waf_csrf_shutdown` | none | rax = status | Shut down CSRF protector |
| `waf_csrf_status` | none | rax = status | Current status |
| `waf_csrf_version` | none | rax = ptr | Version string |
| `waf_csrf_validate` | rdi = request_ctx* | rax = 0 (valid) / neg (invalid) | Validate CSRF token |

### waf_fim

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `waf_fim_init` | none | rax = status | Initialize FIM detector |
| `waf_fim_shutdown` | none | rax = status | Shut down FIM detector |
| `waf_fim_status` | none | rax = status | Current status |
| `waf_fim_version` | none | rax = ptr | Version string |
| `waf_fim_detect` | rdi = request_ctx* | rax = 1 (detected) / 0 (clean), rbx = threat_score | Detect file inclusion |

### waf_cmd

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `waf_cmd_init` | none | rax = status | Initialize command injection detector |
| `waf_cmd_shutdown` | none | rax = status | Shut down command injection detector |
| `waf_cmd_status` | none | rax = status | Current status |
| `waf_cmd_version` | none | rax = ptr | Version string |
| `waf_cmd_detect` | rdi = request_ctx* | rax = 1 (detected) / 0 (clean), rbx = threat_score | Detect command injection |

### waf_deser

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `waf_deser_init` | none | rax = status | Initialize deserialization detector |
| `waf_deser_shutdown` | none | rax = status | Shut down deserialization detector |
| `waf_deser_status` | none | rax = status | Current status |
| `waf_deser_version` | none | rax = ptr | Version string |
| `waf_deser_detect` | rdi = request_ctx* | rax = 1 (detected) / 0 (clean), rbx = threat_score | Detect deserialization attack |

### waf_api

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `waf_api_init` | none | rax = status | Initialize API protection |
| `waf_api_shutdown` | none | rax = status | Shut down API protection |
| `waf_api_status` | none | rax = status | Current status |
| `waf_api_version` | none | rax = ptr | Version string |
| `waf_api_authenticate` | rdi = request_ctx* | rax = 0 (authenticated) / neg (failed), rbx = user_id | Authenticate API request |
| `waf_api_rate_limit` | rdi = api_key*, rsi = key_len | rax = 0 (within limit) / neg (limited), rbx = retry_after_ms | Check API rate limit |

### waf_rate

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `waf_rate_init` | none | rax = status | Initialize rate limiter |
| `waf_rate_shutdown` | none | rax = status | Shut down rate limiter |
| `waf_rate_status` | none | rax = status | Current status |
| `waf_rate_version` | none | rax = ptr | Version string |
| `waf_rate_check` | rdi = client_id* | rax = 0 (within limit) / neg (limited), rbx = retry_after_ms | Check rate limit per client |

### waf_bot

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `waf_bot_init` | none | rax = status | Initialize bot detector |
| `waf_bot_shutdown` | none | rax = status | Shut down bot detector |
| `waf_bot_status` | none | rax = status | Current status |
| `waf_bot_version` | none | rax = ptr | Version string |
| `waf_bot_detect` | rdi = request_ctx* | rax = 1 (bot) / 0 (human), rbx = bot_score (0-100) | Detect bot traffic |
| `waf_bot_score` | rdi = client_ip | rax = bot_score (0-100), rbx = confidence (0-100) | Calculate bot probability score |

### waf_session

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `waf_session_init` | none | rax = status | Initialize session protector |
| `waf_session_shutdown` | none | rax = status | Shut down session protector |
| `waf_session_status` | none | rax = status | Current status |
| `waf_session_version` | none | rax = ptr | Version string |
| `waf_session_validate` | rdi = request_ctx* | rax = 0 (valid) / neg (invalid) | Validate session |
| `waf_session_track` | rdi = request_ctx* | rax = 0 (tracked) | Track session |

### waf_geoip

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `waf_geoip_init` | none | rax = status | Initialize GeoIP filter |
| `waf_geoip_shutdown` | none | rax = status | Shut down GeoIP filter |
| `waf_geoip_status` | none | rax = status | Current status |
| `waf_geoip_version` | none | rax = ptr | Version string |
| `waf_geoip_lookup` | rdi = IP address | rax = country_code, rbx = continent_code | Look up country for an IP |
| `waf_geoip_is_blocked` | rdi = country_code | rax = 1 (blocked) / 0 (allowed) | Check if country is blocked |

### waf_rulec

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `waf_rulec_init` | none | rax = status | Initialize rule compiler |
| `waf_rulec_shutdown` | none | rax = status | Shut down rule compiler |
| `waf_rulec_status` | none | rax = status | Current status |
| `waf_rulec_version` | none | rax = ptr | Version string |
| `waf_rulec_compile` | rdi = rule_src*, rsi = rule_len | rax = compiled_rule_id, rbx = compiled_rule_size | Compile custom WAF rule |

### waf_siem

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `waf_siem_init` | none | rax = status | Initialize SIEM exporter |
| `waf_siem_shutdown` | none | rax = status | Shut down SIEM exporter |
| `waf_siem_status` | none | rax = status | Current status |
| `waf_siem_version` | none | rax = ptr | Version string |
| `waf_siem_export` | rdi = enforcement_event* | rax = status | Export enforcement event to SIEM |

### waf_stats

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `waf_stats_init` | none | rax = status | Initialize stats engine |
| `waf_stats_shutdown` | none | rax = status | Shut down stats engine |
| `waf_stats_status` | none | rax = status | Current status |
| `waf_stats_version` | none | rax = ptr | Version string |
| `waf_stats_record` | rdi = request_ctx*, rsi = action, rdx = attack_type | rax = status | Record enforcement metrics |

---

## WAF Actions

| Code | Symbol | Meaning |
|------|--------|---------|
| 0 | `WAF_ACTION_ALLOW` | Permit traffic |
| 1 | `WAF_ACTION_BLOCK` | Block request |
| 2 | `WAF_ACTION_CHALLENGE` | Challenge client (CAPTCHA) |
| 3 | `WAF_ACTION_LOG` | Log only, allow traffic |
| 4 | `WAF_ACTION_REDIRECT` | Redirect to different destination |

---

## Enforcement Verdicts

| Code | Symbol | Meaning |
|------|--------|---------|
| 0 | `WAF_VERDICT_ALLOW` | Request allowed |
| -1 | `WAF_VERDICT_BLOCK` | Request blocked |
| -2 | `WAF_VERDICT_CHALLENGE` | Challenge required |
| -100 | `WAF_ERROR` | Enforcement error |

---

## Attack Types

| Code | Symbol | Meaning |
|------|--------|---------|
| 1 | `WAF_ATTACK_SQLI` | SQL injection |
| 2 | `WAF_ATTACK_XSS` | Cross-site scripting |
| 3 | `WAF_ATTACK_CSRF` | Cross-site request forgery |
| 4 | `WAF_ATTACK_FILE_INCLUSION` | File inclusion |
| 5 | `WAF_ATTACK_CMD_INJECTION` | Command injection |
| 6 | `WAF_ATTACK_DESERIALIZATION` | Insecure deserialization |
| 7 | `WAF_ATTACK_SCANNER` | Vulnerability scanner |
| 8 | `WAF_ATTACK_BOT` | Automated bot |
| 9 | `WAF_ATTACK_API_ABUSE` | API abuse |
| 10 | `WAF_ATTACK_POLICY_VIOLATION` | Policy violation |

---

## Severity Levels

| Code | Symbol | Meaning |
|------|--------|---------|
| 1 | `WAF_SEV_LOW` | Low severity |
| 2 | `WAF_SEV_MEDIUM` | Medium severity |
| 3 | `WAF_SEV_HIGH` | High severity |
| 4 | `WAF_SEV_CRITICAL` | Critical severity |

---

## Build

```bash
make -C security/waf all
make -C security/waf test
```
