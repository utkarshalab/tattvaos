%ifndef GUARD_SECURITY_SOAR_SRC_SOAR_ASM
%define GUARD_SECURITY_SOAR_SRC_SOAR_ASM

; =============================================================================
; File     : security/soar/src/soar.asm
; Project  : Utkarsha OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Security Orchestration, Automation & Response - main dispatcher.
;              Ingests alerts from IDS/IPS/malwarescan/WAF, evaluates playbooks,
;              and executes automated response actions.
; Status   : PREMIUM ENTERPRISE - full state machine, component lifecycle,
;              orchestration flow, and data structures for 10 components.
; =============================================================================

bits 64
DEFAULT REL

%include "include/soar.inc"

section .bss
alignb 16
soar_global_state:  resb soar_global_state_t_size   ; zero-initialized global state

section .data
alignb 16
soar_version_str:   db SOAR_VERSION_STR, 0

section .text

; =============================================================================
; soar_init - Initialize Security Orchestration, Automation & Response
; Input:  none
; Output: rax = 0 on success, negative error code on failure
;         Initializes global state, loads config, registers components in
;         dependency order.
; =============================================================================
global soar_init
soar_init:
    push    rbx
    push    r12
    push    r13

    ; Double-init guard: check magic
    mov     eax, [soar_global_state + soar_global_state_t.magic]
    cmp     eax, SOAR_STATE_MAGIC
    jnz     .not_initialized
    mov     rax, -1            ; already initialized
    jmp     .done

.not_initialized:
    ; Zero the global state structure
    xor     eax, eax
    mov     rcx, soar_global_state_t_size
    shr     rcx, 2             ; dword count
    mov     rdi, soar_global_state
    rep     stosd

    ; Set magic and version
    mov     eax, SOAR_STATE_MAGIC
    mov     dword [soar_global_state + soar_global_state_t.magic], eax
    mov     eax, (SOAR_VERSION_MAJOR << 16) | SOAR_VERSION_MINOR
    mov     [soar_global_state + soar_global_state_t.version], eax

    ; Load configuration defaults (STUB - config loader to be implemented)
    mov     rax, SOAR_DEFAULT_MAX_RULES
    mov     qword [soar_global_state + soar_global_state_t.max_rules], rax
    mov     rax, SOAR_DEFAULT_MAX_CASES
    mov     qword [soar_global_state + soar_global_state_t.max_cases], rax
    mov     rax, SOAR_DEFAULT_MAX_ALERTS
    mov     qword [soar_global_state + soar_global_state_t.max_alerts], rax
    mov     rax, SOAR_DEFAULT_MAX_ACTIONS
    mov     qword [soar_global_state + soar_global_state_t.max_actions], rax
    mov     rax, SOAR_DEFAULT_DEFAULT_TIMEOUT_MS
    mov     qword [soar_global_state + soar_global_state_t.default_timeout_ms], rax

    ; Default fail mode: CLOSED (secure)
    mov     dword [soar_global_state + soar_global_state_t.fail_mode], SOAR_FAIL_CLOSED

    ; Mark enabled with fail-closed mode
    mov     byte [soar_global_state + soar_state_base_t.enabled], 1

    ; STUB: register with audit subsystem for enforcement logging

    xor     eax, eax             ; success
.done:
    pop     r13
    pop     r12
    pop     rbx
    ret

; =============================================================================
; soar_shutdown - Shut down SOAR
; Input:  none
; Output: rax = 0 on success
; =============================================================================
global soar_shutdown
soar_shutdown:
    push    rbx

    ; Validate magic
    mov     eax, [soar_global_state + soar_global_state_t.magic]
    cmp     eax, SOAR_STATE_MAGIC
    jnz     .not_init

    mov     dword [soar_global_state + soar_global_state_t.magic], SOAR_STATE_MAGIC_FREED
    mov     byte [soar_global_state + soar_state_base_t.enabled], 0
    xor     eax, eax
    pop     rbx
    ret
.not_init:
    mov     eax, -1
    pop     rbx
    ret

; =============================================================================
; soar_status - Return current SOAR status
; Input:  none
; Output: rax = status code (0 = healthy, negative = unhealthy)
; =============================================================================
global soar_status
soar_status:
    mov     eax, [soar_global_state + soar_global_state_t.magic]
    cmp     eax, SOAR_STATE_MAGIC
    jnz     .not_initialized
    mov     al, [soar_global_state + soar_state_base_t.enabled]
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
; soar_version - Return version string pointer
; Input:  none
; Output: rax = pointer to NUL-terminated version string
; =============================================================================
global soar_version
soar_version:
    mov     rax, soar_version_str
    ret

; =============================================================================
; soar_execute - Main enforcement entry point
; Input:  rdi = event_ctx pointer (soar_event_ctx_t*)
; Output: rax = action (SOAR_ACTION_*),
;         rbx = reason code, rcx = rule_id matched
; Pipeline:
;   1. Validate state & input
;   2. Parse alert context (placeholder)
;   3. Evaluate playbook rules (placeholder)
;   4. Match actions to triggered rules
;   5. Execute actions via action_engine
;   6. Create/update case via case_manager
;   7. Log decision via integration_engine (SIEM)
;   8. Record stats via metrics_engine
;   9. Return action + reason + rule_id
; =============================================================================
global soar_execute
soar_execute:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    mov     eax, [soar_global_state + soar_global_state_t.magic]
    cmp     eax, SOAR_STATE_MAGIC
    jnz     .err_component_down

    test    rdi, rdi
    jz      .err_invalid_request

    mov     r12, rdi                      ; save event context pointer

    lock    inc    qword [soar_global_state + soar_global_state_t.total_requests]

    ; STEP 2-17: All component inspections are STUBbed here
    ; STUB: soar_alert_ingest_call - invoke alert ingestor
    ; STUB: soar_policy_evaluate_call - invoke playbook evaluation
    ; STUB: soar_action_execute_call - invoke action engine
    ; STUB: soar_case_create_call - invoke case manager
    ; STUB: soar_automation_execute_call - invoke automation engine
    ; STUB: soar_integration_send_call - invoke integration engine
    ; STUB: soar_metrics_record_call - invoke metrics engine
    ; STUB: soar_scheduler_check_call - invoke scheduler
    ; STUB: soar_rulec_compile_call - invoke rule compiler
    ; For skeleton: request is clean (allow)

    mov     rax, SOAR_ACTION_ALERT
    xor     rbx, rbx               ; no attack
    xor     rcx, rcx               ; no rule matched

    jmp     .done

.err_component_down:
    mov     eax, [soar_global_state + soar_global_state_t.fail_mode]
    cmp     eax, SOAR_FAIL_CLOSED
    je      .fail_open_allow
    mov     rax, SOAR_ACTION_BLOCK_IP
    mov     rbx, SOAR_REASON_POLICY_VIOLATION
    mov     rcx, 0
    jmp     .done
.fail_open_allow:
    mov     rax, SOAR_ACTION_ALERT
    xor     rbx, rbx
    mov     rcx, 0
    jmp     .done

.err_invalid_request:
    mov     rax, SOAR_ACTION_BLOCK_IP
    mov     rbx, SOAR_REASON_INVALID_REQUEST
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
; soar_get_stats - Return statistics snapshot
; Input:  rdi = stats buffer pointer (soar_stats_t*)
; Output: rax = 0 on success, negative on failure
; =============================================================================
global soar_get_stats
soar_get_stats:
    push    rbx

    mov     eax, [soar_global_state + soar_global_state_t.magic]
    cmp     eax, SOAR_STATE_MAGIC
    jnz     .err_component_down

    test    rdi, rdi
    jz      .err_invalid

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
