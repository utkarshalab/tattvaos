%ifndef GUARD_SECURITY_IDS_SRC_IDS_ASM
%define GUARD_SECURITY_IDS_SRC_IDS_ASM

; =============================================================================
; File     : security/ids/src/ids.asm
; Project  : Tattva OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Intrusion Detection System - main dispatcher.
;              Detection-only engine: monitors network traffic and system
;              activities for malicious activity or policy violations. Never
;              blocks traffic (that is IPS's job).
; Status   : PREMIUM SKELETON - full state machine, component lifecycle,
;              inspection pipeline, and data structures. Logic bodies marked
;              STUB with TODO comments.
; =============================================================================

bits 64
DEFAULT REL

%include "include/ids.inc"

section .bss
alignb 16
ids_global_state:  resb ids_global_state_t_size   ; zero-initialized global state

section .data
alignb 16
ids_version_str:   db IDS_VERSION_STR, 0

section .text

; =============================================================================
; ids_init - Initialize Intrusion Detection System
; Input:  none
; Output: rax = 0 on success, negative error code on failure
;         Initializes global state, loads config, registers components in
;         dependency order.
; =============================================================================
global ids_init
ids_init:
    push    rbx
    push    r12
    push    r13

    ; Double-init guard: check magic
    mov     eax, [ids_global_state + ids_global_state_t.magic]
    cmp     eax, IDS_STATE_MAGIC
    jnz     .not_initialized
    mov     rax, -1            ; already initialized
    jmp     .done

.not_initialized:
    ; Zero the global state structure
    xor     eax, eax
    mov     rcx, ids_global_state_t_size
    shr     rcx, 2             ; dword count
    mov     rdi, ids_global_state
    rep     stosd

    ; Set magic and version
    mov     eax, IDS_STATE_MAGIC
    mov     dword [ids_global_state + ids_global_state_t.magic], eax
    mov     eax, (IDS_VERSION_MAJOR << 16) | IDS_VERSION_MINOR
    mov     [ids_global_state + ids_global_state_t.version], eax

    ; Load configuration defaults (STUB - config loader to be implemented)
    mov     rax, IDS_DEFAULT_MAX_ALERTS
    mov     qword [ids_global_state + ids_global_state_t.max_alerts], rax
    mov     rax, IDS_DEFAULT_ALERT_TTL_SECONDS
    mov     qword [ids_global_state + ids_global_state_t.alert_ttl_seconds], rax
    mov     rax, IDS_DEFAULT_DEDUP_WINDOW_MS
    mov     qword [ids_global_state + ids_global_state_t.dedup_window_ms], rax
    mov     rax, IDS_DEFAULT_MAX_RULES
    mov     qword [ids_global_state + ids_global_state_t.max_rules], rax
    mov     rax, IDS_DEFAULT_MAX_STREAMS
    mov     qword [ids_global_state + ids_global_state_t.max_streams], rax
    mov     rax, IDS_DEFAULT_REASSEMBLY_TIMEOUT_MS
    mov     qword [ids_global_state + ids_global_state_t.reassembly_timeout_ms], rax

    ; STUB: Initialize components in dependency order:
    ;   sensor -> reassembler -> analyzer -> rules -> detector ->
    ;   alert -> correlator -> siem -> stats
    mov     dword [ids_global_state + ids_global_state_t.components], IDS_COMP_ALL

    ; Mark enabled
    mov     byte [ids_global_state + ids_global_state_t.enabled], 1

    ; STUB: register with audit subsystem for alert logging
    ; IDS_EMIT_ALERT would be called here for init event

    xor     eax, eax             ; success
.done:
    pop     r13
    pop     r12
    pop     rbx
    ret

; =============================================================================
; ids_shutdown - Shut down Intrusion Detection System
; Input:  none
; Output: rax = 0 on success
; =============================================================================
global ids_shutdown
ids_shutdown:
    push    rbx

    ; Validate magic
    mov     eax, [ids_global_state + ids_global_state_t.magic]
    cmp     eax, IDS_STATE_MAGIC
    jnz     .not_init

    ; STUB: shutdown components in reverse dependency order:
    ;   siem -> stats -> correlator -> alert -> detector -> rules ->
    ;   analyzer -> reassembler -> sensor

    mov     dword [ids_global_state + ids_global_state_t.magic], IDS_STATE_MAGIC_FREED
    mov     byte [ids_global_state + ids_global_state_t.enabled], 0

    xor     eax, eax
.not_init:
    pop     rbx
    ret

; =============================================================================
; ids_status - Return current IDS status
; Input:  none
; Output: rax = status code (0 = healthy, negative = unhealthy)
; =============================================================================
global ids_status
ids_status:
    mov     eax, [ids_global_state + ids_global_state_t.magic]
    cmp     eax, IDS_STATE_MAGIC
    jnz     .not_initialized
    mov     al, [ids_global_state + ids_global_state_t.enabled]
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
; ids_version - Return version string pointer
; Input:  none
; Output: rax = pointer to NUL-terminated version string
; =============================================================================
global ids_version
ids_version:
    mov     rax, ids_version_str
    ret

; =============================================================================
; ids_inspect_packet - Main inspection pipeline entry point
; Input:  rdi = packet_ctx pointer (ids_packet_ctx_t*)
; Output: rax = verdict (IDS_VERDICT_*),
;         rbx = reason code (IDS_REASON_*)
; Pipeline:
;   1. Validate global state & input
;   2. Sensor: capture/validate packet
;   3. Reassembler: TCP stream reassembly, fragment defragmentation
;   4. Analyzer: protocol parsing (HTTP, DNS, TLS, SMB)
;   5. Rules: signature matching against rule database
;   6. Detector: anomaly/behavioral evaluation
;   7. Correlator: cross-source threat correlation
;   8. Alert: emit alert if threat detected
;   9. SIEM: export alert if configured
;   10. Stats: record inspection metrics
;   11. Return verdict + reason code
; =============================================================================
global ids_inspect_packet
ids_inspect_packet:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    ; Validate global state
    mov     eax, [ids_global_state + ids_global_state_t.magic]
    cmp     eax, IDS_STATE_MAGIC
    jnz     .err_component_down

    ; Validate input
    test    rdi, rdi
    jz      .err_invalid_packet

    ; Save packet context pointer
    mov     r12, rdi

    ; Increment total packets counter
    lock    inc    qword [ids_global_state + ids_global_state_t.total_packets]

    ; STEP 1: Sensor - capture/validate packet (STUB)
    ; call ids_sensor_capture(packet_ctx)
    ; If capture fails -> IDS_VERDICT_ERROR

    ; STEP 2: Reassembler - TCP stream reassembly (STUB)
    ; call ids_reassembler_add_packet(packet_ctx)
    ; If reassembly needed, return IDS_VERDICT_CLEAN (wait for more packets)

    ; STEP 3: Analyzer - protocol parsing (STUB)
    ; call ids_analyzer_parse(packet_ctx)
    ; Extract application-layer context

    ; STEP 4: Rules - signature matching (STUB)
    ; call ids_rules_match(packet_ctx)
    ; If signature match -> IDS_VERDICT_THREAT, IDS_REASON_SIGNATURE_MATCH

    ; STEP 5: Detector - anomaly evaluation (STUB)
    ; call ids_detector_evaluate(packet_ctx)
    ; If anomaly threshold exceeded -> IDS_VERDICT_SUSPICIOUS

    ; STEP 6: Correlator - cross-source correlation (STUB)
    ; call ids_correlator_update(src_ip, alert_context)

    ; STEP 7: Alert - emit alert if threat/suspicious (STUB)
    ; call ids_alert_emit(severity, reason, src_ip, dst_ip, ...)

    ; STEP 8: SIEM - export alert if configured (STUB)
    ; call ids_siem_export(alert_ptr)

    ; STEP 9: Stats - record inspection metrics (STUB)
    ; call ids_stats_record(packet_ctx, verdict)

    ; For skeleton: assume clean traffic
    mov     rax, IDS_VERDICT_CLEAN
    xor     rbx, rbx                            ; reason code 0 = no threat

    lock    inc    qword [ids_global_state + ids_global_state_t.total_alerts]
    ; STUB: only increment total_alerts if alert was actually emitted

    jmp     .done

.err_component_down:
    mov     rax, IDS_VERDICT_ERROR
    mov     rbx, IDS_REASON_INSPECTOR_ERROR
    jmp .done

.err_invalid_packet:
    mov     rax, IDS_VERDICT_ERROR
    mov     rbx, IDS_REASON_INSPECTOR_ERROR
    jmp .done

.done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; =============================================================================
; ids_get_stats - Return statistics snapshot
; Input:  rdi = stats buffer pointer (ids_stats_t*)
; Output: rax = 0 on success, negative on failure
; =============================================================================
global ids_get_stats
ids_get_stats:
    push    rbx

    ; Validate global state
    mov     eax, [ids_global_state + ids_global_state_t.magic]
    cmp     eax, IDS_STATE_MAGIC
    jnz     .err_component_down

    ; Validate input
    test    rdi, rdi
    jz      .err_invalid

    ; STUB: copy current statistics to buffer
    ; Real implementation: read atomic counters from global state
    ; and per-component stats into ids_stats_t structure

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
