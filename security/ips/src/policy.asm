%ifndef GUARD_SECURITY_IPS_SRC_POLICY_ASM
%define GUARD_SECURITY_IPS_SRC_POLICY_ASM

; =============================================================================
; File     : security/ips/src/policy.asm
; Project  : Utkarsha OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: IPS Policy - allow/deny lists, rate limits, geo-IP filtering.
;              Evaluates static and dynamic policy rules against enforcement
;              requests. Default-deny posture.
; Status   : PREMIUM SKELETON - rule database, policy evaluation,
;              hot-reload defined. Logic bodies marked STUB.
; =============================================================================

bits 64
DEFAULT REL

%include "include/ips.inc"

section .bss
alignb 16
ips_policy_state:        resb ips_state_base_t_size
ips_policy_rule_head:    resq 1      ; policy rule linked list head
ips_policy_rule_count:   resq 1
ips_policy_default_action: resd 1    ; default action (IPS_ACTION_DROP = deny)
ips_policy_reload_pending: resb 1    ; hot-reload requested flag

section .data
alignb 16
ips_policy_version_str: db IPS_VERSION_STR, 0

section .text

; =============================================================================
; ips_policy_init - Initialize policy component
; Input:  none
; Output: rax = 0 on success, negative on failure
; =============================================================================
global ips_policy_init
ips_policy_init:
    push    rbx

    mov     dword [ips_policy_state + ips_state_base_t.magic], IPS_STATE_MAGIC
    mov     dword [ips_policy_state + ips_state_base_t.version], IPS_VERSION_MAJOR
    mov     byte [ips_policy_state + ips_state_base_t.enabled], 1

    mov     qword [ips_policy_rule_head], 0
    mov     qword [ips_policy_rule_count], 0
    mov     dword [ips_policy_default_action], IPS_ACTION_DROP   ; default-deny
    mov     byte [ips_policy_reload_pending], 0

    ; STUB: allocate policy rule memory pool
    ; STUB: load default policies from config
    ; STUB: compile rules into fast-match structure
    ; STUB: register file watcher for hot-reload

    xor     eax, eax
    pop     rbx
    ret

; =============================================================================
; ips_policy_shutdown - Shut down policy component
; Input:  none
; Output: rax = 0 on success
; =============================================================================
global ips_policy_shutdown
ips_policy_shutdown:
    push    rbx

    mov     eax, [ips_policy_state + ips_state_base_t.magic]
    cmp     eax, IPS_STATE_MAGIC
    jnz     .not_init

    ; STUB: free all policy rules
    ; STUB: unregister file watcher

    mov     dword [ips_policy_state + ips_state_base_t.magic], IPS_STATE_MAGIC_FREED
    mov     byte [ips_policy_state + ips_state_base_t.enabled], 0

    xor     eax, eax
    pop     rbx
    ret
.not_init:
    mov     eax, -1
    pop     rbx
    ret

; =============================================================================
; ips_policy_status - Return current status
; Input:  none
; Output: rax = status code
; =============================================================================
global ips_policy_status
ips_policy_status:
    mov     eax, [ips_policy_state + ips_state_base_t.magic]
    cmp     eax, IPS_STATE_MAGIC
    jnz     .not_init
    mov     al, [ips_policy_state + ips_state_base_t.enabled]
    test    al, al
    jz      .disabled
    xor     eax, eax
    ret
.disabled:
    mov     eax, -1
    ret
.not_init:
    mov     eax, -2
    ret

; =============================================================================
; ips_policy_version - Return version string pointer
; Input:  none
; Output: rax = pointer to NUL-terminated version string
; =============================================================================
global ips_policy_version
ips_policy_version:
    mov     rax, ips_policy_version_str
    ret

; =============================================================================
; ips_policy_load - Load rules from file/memory
; Input:  rdi = rules source pointer, rsi = source size
; Output: rax = rules loaded count (positive) or negative error code
; =============================================================================
global ips_policy_load
ips_policy_load:
    push    rbx

    mov     eax, [ips_policy_state + ips_state_base_t.magic]
    cmp     eax, IPS_STATE_MAGIC
    jnz     .err_component_down

    test    rdi, rdi
    jz      .err_invalid
    test    rsi, rsi
    jz      .err_invalid

    ; STUB: parse rule format (allow/deny rules with 5-tuple matching)
    ; STUB: validate rule fields
    ; STUB: allocate ips_policy_rule_t from pool
    ; STUB: insert into rule linked list sorted by priority
    ; STUB: set reload_pending = 0 on success

    mov     rax, 0   ; STUB: 0 rules loaded
    jmp .done

.err_component_down:
    mov     rax, -2
    jmp .done
.err_invalid:
    mov     rax, -3
    jmp .done

.done:
    pop     rbx
    ret

; =============================================================================
; ips_policy_evaluate - Evaluate enforcement request against policies
; Input:  rdi = enforce_ctx pointer (ips_enforce_ctx_t*)
; Output: rax = action (IPS_ACTION_ALLOW or IPS_ACTION_DROP),
;         rbx = reason code (0 = allowed, IPS_REASON_POLICY_VIOLATION = denied)
; Algorithm:
;   1. Walk policy rule list, find matching rules (5-tuple)
;   2. Apply highest-priority matching rule
;   3. If no rule matches -> default action (IPS_ACTION_DROP = deny)
; =============================================================================
global ips_policy_evaluate
ips_policy_evaluate:
    push    rbx
    push    r12

    mov     eax, [ips_policy_state + ips_state_base_t.magic]
    cmp     eax, IPS_STATE_MAGIC
    jnz     .err_component_down

    test    rdi, rdi
    jz      .err_invalid

    ; STEP 1: Walk policy rule list
    ; STUB: check src_ip, dst_ip, src_port, dst_port, protocol match
    ; STUB: apply highest-priority match
    ; STUB: if no match, return default_action (deny)

    ; For skeleton: default-deny (no rules loaded yet)
    mov     eax, [ips_policy_default_action]
    mov     ebx, IPS_REASON_POLICY_VIOLATION
    jmp .done

.err_component_down:
    mov     rax, -2
    xor     rbx, rbx
    jmp .done
.err_invalid:
    mov     rax, -3
    xor     rbx, rbx
    jmp .done

.done:
    pop     r12
    pop     rbx
    ret

%endif
