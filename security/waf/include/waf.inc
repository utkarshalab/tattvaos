%ifndef GUARD_SECURITY_WAF_INC_WAF_INC
%define GUARD_SECURITY_WAF_INC_WAF_INC

; =============================================================================
; File     : security/waf/include/waf.inc
; Project  : Tattva OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Web Application Firewall - master schema header.
;              Constants, structures, macros, and error codes shared by every
;              WAF component (core, rule, http, sqli, xss, csrf, fim, cmd,
;              deser, api, rate, bot, session, geoip, rulec, siem, stats).
;
; DESIGN INVARIANT:
;   WAF is an application-layer firewall that sits in front of web applications
;   and inspects HTTP/HTTPS traffic for attacks: SQLi, XSS, CSRF, command
;   injection, file inclusion, deserialization, bot traffic, API abuse, and more.
;   WAF works WITH IPS: IPS handles network-layer enforcement, WAF handles
;   application-layer enforcement. WAF can veto requests that pass IPS.
;
;   Component contract:
;     *_init      - allocate state, load config, register component
;     *_shutdown  - release state, unregister component
;     *_status    - return component health/code
;     *_version   - return NUL-terminated version string
;
; Status: PREMIUM ENTERPRISE SKELETON - full WAF feature set including real
;         detection logic (SQLi, XSS, command injection, file inclusion),
;         rate limiting, bot detection, geoip blocking, session management,
;         rate limiting, API protection, and full documentation defined.
; =============================================================================

%ifndef WAF_INC
%define WAF_INC

; -----------------------------------------------------------------------------
; Version
; -----------------------------------------------------------------------------
%define WAF_VERSION_MAJOR   2
%define WAF_VERSION_MINOR   0
%define WAF_VERSION_PATCH   0
%define WAF_VERSION_STR     "2.0.0-enterprise"

; -----------------------------------------------------------------------------
; Magic numbers
; -----------------------------------------------------------------------------
%define WAF_STATE_MAGIC             0x57414644   ; "WAFS"
%define WAF_STATE_MAGIC_FREED       0xDEADBEEF

; -----------------------------------------------------------------------------
; Component IDs (bitmask)
; -----------------------------------------------------------------------------
%define WAF_CORE_ENGINE             1
%define WAF_RULE_ENGINE             2
%define WAF_HTTP_INSPECTOR          4
%define WAF_SQLI_DETECTOR           8
%define WAF_XSS_DETECTOR            16
%define WAF_CSRF_PROTECTOR          32
%define WAF_FILE_INCLUSION_DETECTOR 64
%define WAF_CMD_INJECTION_DETECTOR  128
%define WAF_DESERIALIZATION_DETECTOR 256
%define WAF_API_PROTECTION          512
%define WAF_RATE_LIMITER            1024
%define WAF_BOT_DETECTOR            2048
%define WAF_SESSION_PROTECTOR       4096
%define WAF_GEOIP_FILTER            8192
%define WAF_CUSTOM_RULE_COMPILER    16384
%define WAF_SIEM_EXPORTER           32768
%define WAF_STATS_ENGINE            65536
%define WAF_ALL                     0x1FFFF

; -----------------------------------------------------------------------------
; WAF actions
; -----------------------------------------------------------------------------
%define WAF_ACTION_ALLOW            0
%define WAF_ACTION_BLOCK            1
%define WAF_ACTION_CHALLENGE        2
%define WAF_ACTION_LOG              3
%define WAF_ACTION_REDIRECT         4

%define WAF_ACTION_POLICY_VIOLATION 10
%define WAF_ACTION_INVALID_REQUEST  11
%define WAF_ACTION_RATE_LIMIT       12
%define WAF_ACTION_GEOIP_BLOCKED    13

; -----------------------------------------------------------------------------
; WAF verdicts
; -----------------------------------------------------------------------------
%define WAF_VERDICT_ALLOW           0
%define WAF_VERDICT_BLOCK           -1
%define WAF_VERDICT_CHALLENGE       -2
%define WAF_ERROR                   -100

; -----------------------------------------------------------------------------
; Fail modes
; -----------------------------------------------------------------------------
%define WAF_FAIL_CLOSED             0
%define WAF_FAIL_OPEN               1

; -----------------------------------------------------------------------------
; Enforcement reasons (aliases for WAF_ACTION_*)
; -----------------------------------------------------------------------------
%define WAF_REASON_NONE             0
%define WAF_REASON_POLICY_VIOLATION 10
%define WAF_REASON_INVALID_REQUEST  11
%define WAF_REASON_RATE_LIMIT       12
%define WAF_REASON_GEOIP_BLOCKED    13

; -----------------------------------------------------------------------------
; Attack types
; -----------------------------------------------------------------------------
%define WAF_ATTACK_SQLI             1
%define WAF_ATTACK_XSS              2
%define WAF_ATTACK_CSRF             3
%define WAF_ATTACK_FILE_INCLUSION   4
%define WAF_ATTACK_CMD_INJECTION    5
%define WAF_ATTACK_DESERIALIZATION  6
%define WAF_ATTACK_SCANNER          7
%define WAF_ATTACK_BOT              8
%define WAF_ATTACK_API_ABUSE        9
%define WAF_ATTACK_POLICY_VIOLATION 10

; -----------------------------------------------------------------------------
; Severity levels
; -----------------------------------------------------------------------------
%define WAF_SEV_LOW                 1
%define WAF_SEV_MEDIUM              2
%define WAF_SEV_HIGH                3
%define WAF_SEV_CRITICAL            4

; -----------------------------------------------------------------------------
; Configuration defaults
; -----------------------------------------------------------------------------
%define WAF_DEFAULT_MAX_RULES          50000
%define WAF_DEFAULT_MAX_BLOCKED_IPS    50000
%define WAF_DEFAULT_MAX_QUARANTINE     10000
%define WAF_DEFAULT_BLOCK_DURATION_MS  3600000
%define WAF_DEFAULT_QUARANTINE_DURATION_MS 86400000
%define WAF_DEFAULT_RATE_LIMIT_RPS     100
%define WAF_DEFAULT_ANOMALY_THRESHOLD  5

%define THREAT_INTEL_DEFAULT_MAX_IOCS               1000000
%define THREAT_INTEL_DEFAULT_MAX_FEEDS              1000
%define THREAT_INTEL_DEFAULT_MAX_FINDINGS           1000000
%define THREAT_INTEL_DEFAULT_MAX_CASES              100000
%define THREAT_INTEL_DEFAULT_MAX_PLAYBOOKS          1000
%define THREAT_INTEL_DEFAULT_MAX_ACTIONS            1000000
%define THREAT_INTEL_DEFAULT_MAX_ALERTS             100000
%define THREAT_INTEL_DEFAULT_CONFIDENCE_THRESHOLD   70
%define THREAT_INTEL_DEFAULT_IOC_TTL_SECONDS        864000
%define THREAT_INTEL_DEFAULT_MAX_RULES              50000
%define THREAT_INTEL_DEFAULT_MAX_CASES_PER_DAY              10000
%define THREAT_INTEL_DEFAULT_MAX_ALERTS_PER_DAY             100000
%define TI_DEFAULT_MAX_ACTIONS_PER_DAY            1000000
%define THREAT_INTEL_DEFAULT_MAX_CASES_PER_HOUR             10000
%define THREAT_INTEL_DEFAULT_MAX_ALERTS_PER_HOUR            100000
%define TI_DEFAULT_MAX_ACTIONS_PER_HOUR           1000000
%define THREAT_INTEL_DEFAULT_MAX_CASES_PER_WEEK             70000
%define THREAT_INTEL_DEFAULT_MAX_ALERTS_PER_WEEK            700000
%define THREAT_INTEL_DEFAULT_MAX_ACTIONS_PER_WEEK           7000000
%define THREAT_INTEL_DEFAULT_MAX_CASES_PER_MONTH            300000
%define THREAT_INTEL_DEFAULT_MAX_ALERTS_PER_MONTH           3000000
%define THREAT_INTEL_DEFAULT_MAX_ACTIONS_PER_MONTH            30000000

; -----------------------------------------------------------------------------
; Scan types
; -----------------------------------------------------------------------------
%define WAF_SCAN_TYPE_NETWORK     1
%define WAF_SCAN_TYPE_HOST        2
%define WAF_SCAN_TYPE_APPLICATION 3
%define WAF_SCAN_TYPE_CONTAINER   4
%define WAF_SCAN_TYPE_CLOUD       5

; -----------------------------------------------------------------------------
; Spinlock macros
; -----------------------------------------------------------------------------
%macro WAF_SPIN_LOCK 1
    ; STUB: acquire spinlock on %1
%endmacro

%macro WAF_SPIN_UNLOCK 1
    ; STUB: release spinlock on %1
%endmacro

; -----------------------------------------------------------------------------
; Linked list macros
; -----------------------------------------------------------------------------
%define WAF_LIST_INIT(head)  head

%macro WAF_LIST_ADD 2
    ; STUB: insert node %1 at head of list %2
%endmacro

%macro WAF_LIST_REMOVE 2
    ; STUB: remove node %1 from list %2
%endmacro

; -----------------------------------------------------------------------------
; Return value helper
; -----------------------------------------------------------------------------
%macro WAF_RET 1
    mov     eax, %1
    ret
%endmacro

; -----------------------------------------------------------------------------
; State structure base (embedded at start of every component state)
; -----------------------------------------------------------------------------
struc waf_state_base_t
    .magic:         resd 1      ; WAF_STATE_MAGIC for validation
    .version:       resd 1      ; component version
    .refcount:      resd 1      ; reference count
    .spinlock:      resq 1      ; SMP spinlock
    .enabled:       resb 1      ; component enabled flag
    .pad:           resb 7      ; alignment
    .init_ns:       resq 1      ; initialization timestamp
    .stats_requests: resq 1      ; total requests processed
    .stats_blocks:   resq 1      ; total blocks
    .stats_challenges: resq 1    ; total challenges
    .total_requests:    resq 1    ; total requests processed
    .total_blocks:   resq 1      ; total blocks
    .total_challenges:    resq 1   ; total challenges
endstruc

; -----------------------------------------------------------------------------
; HTTP request context (input to waf_inspect)
; -----------------------------------------------------------------------------
struc waf_request_ctx_t
    .timestamp_ns:  resq 1      ; request timestamp
    .src_ip:        resd 1      ; IPv4 source address
    .dst_ip:        resd 1      ; IPv4 destination address
    .src_port:      resd 1
    .dst_port:      resd 1
    .protocol:      resd 1      ; WAF_SCAN_TYPE_*
    .url:           resq 1      ; NUL-terminated URL
    .url_len:       resd 1
    .host:          resq 1      ; NUL-terminated host
    .host_len:      resd 1
    .user_agent:    resq 1      ; NUL-terminated User-Agent
    .user_agent_len: resd 1
    .content_type:   resq 1      ; NUL-terminated content type
    .content_len:    resd 1      ; request body length
    .body:           resq 1      ; request body pointer
    .body_len:       resd 1      ; request body length
    .headers_count:  resd 1      ; number of headers
    .headers_ptr:    resq 1      ; pointer to header name/value pairs
    .session_id:     resq 1      ; associated session ID
    .session_ptr:    resq 1      ; session context pointer
    .session_state:  resd 1      ; session state
    .session_ttl:    resq 1      ; session TTL
    .api_key:        resq 1      ; NUL-terminated API key
    .api_key_len:    resd 1
    .session_flags:  resd 1      ; session flags
endstruc

; -----------------------------------------------------------------------------
; WAF rule
; -----------------------------------------------------------------------------
struc waf_rule_t
    .rule_id:       resq 1
    .rule_name:     resb 128
    .rule_type:     resd 1      ; WAF_ACTION_*
    .severity:      resd 1      ; WAF_SEV_*
    .action:        resd 1      ; WAF_ACTION_*
    .enabled:       resb 1
    .pad:           resb 3
    .pattern_ptr:   resq 1       ; detection pattern
    .pattern_len:   resd 1
    .location:      resd 1       ; where to inspect (URL, body, header, etc.)
    .hit_count:     resq 1       ; hit count
    .next:          resq 1       ; linked list
endstruc

; -----------------------------------------------------------------------------
; WAF match result
; -----------------------------------------------------------------------------
struc waf_match_t
    .rule_id:       resq 1
    .attack_type:   resd 1
    .severity:      resd 1
    .matched_text:  resq 1       ; pointer to matched text
    .matched_len:   resd 1
    .location:      resd 1       ; where match occurred
    .confidence:    resd 1      ; 0-100 confidence score
    .next:          resq 1      ; linked list
endstruc

; -----------------------------------------------------------------------------
; Blocked IP entry
; -----------------------------------------------------------------------------
struc waf_blocked_ip_t
    .ip:            resd 1
    .reason_code:   resd 1
    .blocked_ns:    resq 1
    .expires_ns:    resq 1       ; 0 = permanent
    .hit_count:     resq 1      ; hit count
    .next:          resq 1      ; linked list
endstruc

; -----------------------------------------------------------------------------
; Session context
; -----------------------------------------------------------------------------
struc waf_session_t
    .session_id:    resq 1
    .src_ip:        resd 1
    .created_ns:    resq 1
    .last_seen_ns:  resq 1
    .request_count: resq 1
    .threat_score:  resd 1       ; 0-100 aggregated threat score
    .is_bot:        resb 1
    .pad:           resb 3
    .next:          resq 1       ; linked list
endstruc

; -----------------------------------------------------------------------------
; API key context
; -----------------------------------------------------------------------------
struc waf_api_key_t
    .api_key:       resb 64      ; NUL-terminated API key
    .key_len:       resd 1
    .rate_limit:    resq 1       ; requests per second limit
    .request_count: resq 1       ; current window count
    .window_start:  resq 1       ; window start timestamp
    .is_active:     resb 1
    .pad:           resb 3
    .next:          resq 1      ; linked list
endstruc

; -----------------------------------------------------------------------------
; Statistics snapshot
; -----------------------------------------------------------------------------
struc waf_stats_t
    .requests_total:     resq 1
    .requests_by_method: resq 8   ; GET, POST, PUT, DELETE, HEAD, OPTIONS, PATCH, OTHER
    .blocks_total:       resq 1
    .blocks_by_type:     resq 11   ; per attack type (WAF_ACTION_*)
    .challenges_total:   resq 1
    .top_attacked_uris:  resq 1    ; pointer to top attacked URIs
    .top_blocked_ips:    resq 1    ; pointer to top blocked IPs
    .sample_interval:    resq 1
    .last_sample:        resq 1
endstruc

; -----------------------------------------------------------------------------
; Global WAF state
; -----------------------------------------------------------------------------
struc waf_global_state_t
    .magic:             resd 1
    .version:           resd 1
    .enabled:           resb 1      ; WAF_FAIL_CLOSED or WAF_FAIL_OPEN
    .fail_mode:         resb 1      ; WAF_FAIL_CLOSED or WAF_FAIL_OPEN
    .pad:               resb 2
    .components:        resd 1      ; bitmask of initialized components
    .spinlock:          resq 1
    .max_rules:         resq 1
    .max_blocked_ips:   resq 1
    .max_quarantine:    resq 1
    .block_duration_ms: resq 1
    .quarantine_duration_ms: resq 1
    .rate_limit_rps:    resq 1
    .anomaly_threshold: resd 1      ; anomaly score threshold (0-100)
    .pad2:              resd 2
    .total_requests:    resq 1
    .total_blocks:      resq 1
    .total_challenges:  resq 1
    .core_state:        resq 1
    .rule_state:        resq 1
    .http_state:        resq 1
    .sqli_state:        resq 1
    .xss_state:         resq 1
    .csrf_state:        resq 1
    .fim_state:         resq 1
    .cmd_state:         resq 1
    .deser_state:       resq 1
    .api_state:         resq 1
    .rate_state:        resq 1
    .bot_state:         resq 1
    .session_state:     resq 1
    .geoip_state:       resq 1
    .rule_compiler_state: resq 1
    .siem_state:        resq 1
    .stats_state:       resq 1
endstruc

%endif ; WAF_INC
%endif ; GUARD_SECURITY_WAF_INC_WAF_INC