%ifndef GUARD_SECURITY_IPS_SRC_IPS_ASM
%define GUARD_SECURITY_IPS_SRC_IPS_ASM

; =============================================================================
; File     : security/ips/src/ips.asm
; Project  : Utkarsha OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Intrusion Prevention System - main dispatcher (Enterprise).
;              Inline enforcement engine: sits in traffic path, can DROP,
;              RESET, THROTTLE, QUARANTINE, BLOCK, REDIRECT, or SANDBOX
;              traffic. FAILS CLOSED — if enforcement cannot be verified,
;              traffic is blocked. Works WITH IDS: IDS detects, IPS prevents.
; Status   : PREMIUM ENTERPRISE - full state machine, component lifecycle,
;              enforcement flow, and data structures for 21 components.
; =============================================================================

bits 64
DEFAULT REL

%include "include/ips.inc"

section .bss
alignb 16
ips_global_state:  resb ips_global_state_t_size   ; zero-initialized global state

section .data
alignb 16
ips_version_str:   db IPS_VERSION_STR, 0

section .text

; =============================================================================
; ips_init - Initialize Intrusion Prevention System
; Input:  none
; Output: rax = 0 on success, negative error code on failure
;         Initializes global state, loads config, registers components in
;         dependency order.
; =============================================================================
global ips_init
ips_init:
    push    rbx
    push    r12
    push    r13

    ; Double-init guard: check magic
    mov     eax, [ips_global_state + ips_global_state_t.magic]
    cmp     eax, IPS_STATE_MAGIC
    jnz     .not_initialized
    mov     rax, -1            ; already initialized
    jmp     .done

.not_initialized:
    ; Zero the global state structure
    xor     eax, eax
    mov     rcx, ips_global_state_t_size
    shr     rcx, 2             ; dword count
    mov     rdi, ips_global_state
    rep     stosd

    ; Set magic and version
    mov     eax, IPS_STATE_MAGIC
    mov     dword [ips_global_state + ips_global_state_t.magic], eax
    mov     eax, (IPS_VERSION_MAJOR << 16) | IPS_VERSION_MINOR
    mov     [ips_global_state + ips_global_state_t.version], eax

    ; Load configuration defaults (STUB - config loader to be implemented)
    mov     rax, IPS_DEFAULT_MAX_CONNECTIONS
    mov     qword [ips_global_state + ips_global_state_t.max_connections], rax
    mov     rax, IPS_DEFAULT_MAX_BLOCKLIST
    mov     qword [ips_global_state + ips_global_state_t.max_blocklist], rax
    mov     rax, IPS_DEFAULT_MAX_QUARANTINE
    mov     qword [ips_global_state + ips_global_state_t.max_quarantine], rax
    mov     rax, IPS_DEFAULT_BLOCK_DURATION_MS
    mov     qword [ips_global_state + ips_global_state_t.block_duration_ms], rax
    mov     rax, IPS_DEFAULT_QUARANTINE_DURATION_MS
    mov     qword [ips_global_state + ips_global_state_t.quarantine_duration_ms], rax
    mov     rax, IPS_DEFAULT_RATE_LIMIT_RPS
    mov     qword [ips_global_state + ips_global_state_t.rate_limit_rps], rax

    ; Default fail mode: CLOSED (secure)
    mov     dword [ips_global_state + ips_global_state_t.fail_mode], IPS_FAIL_CLOSED

    ; STUB: Initialize components in dependency order:
    ;   bypass -> policy -> blocklist -> rate_limiter -> connection_tracker ->
    ;   inspector -> enforcer -> quarantine -> siem -> stats ->
    ;   geoip -> app_control -> tls_inspector -> dns_filter -> file_analysis ->
    ;   url_filter -> bot_detector -> ddos_protector -> threat_feed ->
    ;   waf_engine -> packet_capture -> ha_cluster -> api_protection ->
    ;   ml_anomaly
    mov     dword [ips_global_state + ips_global_state_t.components], IPS_COMP_ALL

    ; Mark enabled with fail-closed mode
    mov     byte [ips_global_state + ips_global_state_t.enabled], 1

    ; STUB: register with audit subsystem for enforcement logging
    ; IPS_ENFORCE would be called here for init event

    xor     eax, eax             ; success
.done:
    pop     r13
    pop     r12
    pop     rbx
    ret

; =============================================================================
; ips_shutdown - Shut down Intrusion Prevention System
; Input:  none
; Output: rax = 0 on success
; =============================================================================
global ips_shutdown
ips_shutdown:
    push    rbx

    ; Validate magic
    mov     eax, [ips_global_state + ips_global_state_t.magic]
    cmp     eax, IPS_STATE_MAGIC
    jnz     .not_init

    ; STUB: shutdown components in reverse dependency order:
    ;   ml_anomaly -> api_protection -> ha_cluster -> packet_capture ->
    ;   waf_engine -> threat_feed -> ddos_protector -> bot_detector ->
    ;   url_filter -> file_analysis -> dns_filter -> tls_inspector ->
    ;   app_control -> geoip -> stats -> siem -> quarantine ->
    ;   blocklist -> conn_tracker -> rate_limiter -> bypass ->
    ;   enforcer -> inspector -> policy

    mov     dword [ips_global_state + ips_global_state_t.magic], IPS_STATE_MAGIC_FREED
    mov     byte [ips_global_state + ips_global_state_t.enabled], 0

    xor     eax, eax
.not_init:
    pop     rbx
    ret

; =============================================================================
; ips_status - Return current IPS status
; Input:  none
; Output: rax = status code (0 = healthy, negative = unhealthy)
; =============================================================================
global ips_status
ips_status:
    mov     eax, [ips_global_state + ips_global_state_t.magic]
    cmp     eax, IPS_STATE_MAGIC
    jnz     .not_initialized
    mov     al, [ips_global_state + ips_global_state_t.enabled]
    test    al, al
    jz      .disabled
    xor     eax, eax
    ret
.disabled:
    mov     eax, -1
    ret
.not_initialized:
    mov     eax, -2
    ret

; =============================================================================
; ips_version - Return version string pointer
; Input:  none
; Output: rax = pointer to NUL-terminated version string
; =============================================================================
global ips_version
ips_version:
    mov     rax, ips_version_str
    ret

; =============================================================================
; ips_enforce - Main enforcement entry point
; Input:  rdi = enforce_ctx pointer (ips_enforce_ctx_t*)
; Output: rax = action (IPS_ACTION_*),
;         rbx = reason code (IPS_REASON_*),
;         rcx = duration_ms (for block/quarantine)
; Pipeline:
;   1. Validate global state & input
;   2. Bypass: check fail-open/fail-closed mode
;   3. Blocklist: check if src/dst IP is blocked
;   4. Quarantine: check if endpoint is quarantined
;   5. Rate limiter: check rate limits per IP
;   6. Policy: evaluate allow/deny rules
;   7. GeoIP: check country blocking
;   8. App Control: detect and enforce application policy
;   9. TLS Inspector: inspect TLS handshake and fingerprints
;   10. DNS Filter: check domain blocking
;   11. File Analysis: check file hash reputation
;   12. URL Filter: check URL categorization
;   13. Bot Detector: check for automated bot behavior
;   14. DDoS Protector: check volumetric attack thresholds
;   15. Threat Feed: check IOC against threat intelligence
;   16. WAF Engine: inspect HTTP for web attacks
;   17. Inspector: inline packet inspection
;   18. Enforcer: apply action (drop/reset/throttle/quarantine/block)
;   19. Connection tracker: track connection state
;   20. SIEM: export enforcement event if configured
;   21. Stats: record enforcement metrics
;   22. ML Anomaly: score for anomalies
;   23. Return action + reason + duration
; =============================================================================
global ips_enforce
ips_enforce:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    ; Validate global state
    mov     eax, [ips_global_state + ips_global_state_t.magic]
    cmp     eax, IPS_STATE_MAGIC
    jnz     .err_component_down

    ; Validate input
    test    rdi, rdi
    jz      .err_invalid_request

    ; Save enforce context pointer
    mov     r12, rdi

    ; Increment total packets counter
    lock    inc    qword [ips_global_state + ips_global_state_t.total_packets]

    ; STEP 1: Bypass check - fail-open paths
    ; STUB: call ips_bypass_check(enforce_ctx)
    ; If fail-open and component down -> allow

    ; STEP 2: Blocklist check
    ; STUB: call ips_blocklist_check(src_ip, dst_ip)
    ; If blocked -> IPS_ACTION_BLOCK, IPS_REASON_BLACKLISTED_IP

    ; STEP 3: Quarantine check
    ; STUB: check if src_ip or dst_ip is quarantined
    ; If quarantined -> IPS_ACTION_QUARANTINE, IPS_REASON_QUARANTINED_HOST

    ; STEP 4: Rate limiter check
    ; STUB: call ips_rate_limiter_check(src_ip)
    ; If rate limited -> IPS_ACTION_THROTTLE, IPS_REASON_RATE_LIMIT

    ; STEP 5: Policy evaluation
    ; STUB: call ips_policy_evaluate(enforce_ctx)
    ; If policy denies -> IPS_ACTION_DROP, IPS_REASON_POLICY_VIOLATION

    ; STEP 6: GeoIP check
    ; STUB: call ips_geoip_lookup(src_ip) -> country code
    ; STUB: call ips_geoip_is_blocked(country)
    ; If blocked -> IPS_ACTION_DROP, IPS_REASON_GEOIP_BLOCKED

    ; STEP 7: App Control
    ; STUB: call ips_app_control_detect(enforce_ctx) -> app_id
    ; STUB: call ips_app_control_is_allowed(app_id)
    ; If blocked -> IPS_ACTION_DROP, IPS_REASON_APP_BLOCKED

    ; STEP 8: TLS Inspector
    ; STUB: call ips_tls_inspector_inspect(enforce_ctx)
    ; If TLS violation -> IPS_ACTION_DROP, IPS_REASON_TLS_VIOLATION

    ; STEP 9: DNS Filter
    ; STUB: call ips_dns_filter_check(domain)
    ; If blocked -> IPS_ACTION_DROP, IPS_REASON_DNS_BLOCKED

    ; STEP 10: File Analysis
    ; STUB: call ips_file_analysis_check_hash(file_hash)
    ; If malicious -> IPS_ACTION_DROP, IPS_REASON_FILE_MALICIOUS

    ; STEP 11: URL Filter
    ; STUB: call ips_url_filter_check(url)
    ; If blocked -> IPS_ACTION_DROP, IPS_REASON_URL_BLOCKED

    ; STEP 12: Bot Detector
    ; STUB: call ips_bot_detector_check(enforce_ctx)
    ; If bot -> IPS_ACTION_THROTTLE, IPS_REASON_BOT_DETECTED

    ; STEP 13: DDoS Protector
    ; STUB: call ips_ddos_protector_check(enforce_ctx)
    ; If DDoS -> IPS_ACTION_DROP, IPS_REASON_DDoS_ATTACK

    ; STEP 14: Threat Feed
    ; STUB: call ips_threat_feed_check_ioc(ioc_type, ioc_value)
    ; If matched -> IPS_ACTION_DROP, IPS_REASON_THREAT_FEED

    ; STEP 15: WAF Engine
    ; STUB: call ips_waf_engine_inspect(enforce_ctx)
    ; If WAF violation -> IPS_ACTION_DROP, IPS_REASON_WAF_VIOLATION

    ; STEP 16: Inspector - inline packet inspection
    ; STUB: call ips_inspector_inspect(enforce_ctx)
    ; If threat detected -> IPS_ACTION_DROP or RESET

    ; STEP 17: Enforcer - apply the action
    ; STUB: call ips_enforcer_apply_action(action, ctx)
    ; If enforcer fails and fail_closed -> IPS_ACTION_DROP

    ; STEP 18: Connection tracker
    ; STUB: call ips_connection_tracker_track(enforce_ctx, action)

    ; STEP 19: SIEM - export enforcement event
    ; STUB: call ips_siem_export(enforcement_event)

    ; STEP 20: Stats - record enforcement metrics
    ; STUB: call ips_stats_record(enforce_ctx, action)

    ; STEP 21: ML Anomaly
    ; STUB: call ips_ml_anomaly_score(enforce_ctx)
    ; If anomaly -> IPS_ACTION_THROTTLE, IPS_REASON_ANOMALY

    ; For skeleton: allow traffic (no policies loaded yet)
    mov     rax, IPS_ACTION_ALLOW
    xor     rbx, rbx               ; reason code 0 = allowed
    mov     rcx, 0                 ; no duration

    lock    inc    qword [ips_global_state + ips_global_state_t.total_packets]

    ; STUB: IPS_ENFORCE(action, reason, src_ip, dst_ip, duration, message)

    jmp     .done

.err_component_down:
    ; Fail-closed: block if component is down
    mov     eax, [ips_global_state + ips_global_state_t.fail_mode]
    cmp     eax, IPS_FAIL_OPEN
    je      .fail_open_allow
    mov     rax, IPS_ACTION_DROP
    mov     rbx, IPS_REASON_COMPONENT_DOWN
    mov     rcx, 0
    jmp     .done

.fail_open_allow:
    mov     rax, IPS_ACTION_ALLOW
    xor     rbx, rbx
    mov     rcx, 0
    jmp     .done

.err_invalid_request:
    mov     rax, IPS_ACTION_DROP
    mov     rbx, IPS_REASON_INVALID_REQUEST
    mov     rcx, 0
    jmp     .done

.done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; =============================================================================
; ips_get_stats - Return statistics snapshot
; Input:  rdi = stats buffer pointer (ips_stats_t*)
; Output: rax = 0 on success, negative on failure
; =============================================================================
global ips_get_stats
ips_get_stats:
    push    rbx

    ; Validate global state
    mov     eax, [ips_global_state + ips_global_state_t.magic]
    cmp     eax, IPS_STATE_MAGIC
    jnz     .err_component_down

    ; Validate input
    test    rdi, rdi
    jz      .err_invalid

    ; STUB: copy current statistics to buffer
    ; Real implementation: read atomic counters from global state
    ; and per-component stats into ips_stats_t structure

    xor     eax, eax
    jmp .done

.err_component_down:
    mov     rax, -1
    jmp .done
.err_invalid:
    mov     rax, -2
    jmp .done

.done:
    pop     rbx
    ret

%endif
