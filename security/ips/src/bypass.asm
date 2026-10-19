%ifndef GUARD_SECURITY_IPS_SRC_BYPASS_ASM
%define GUARD_SECURITY_IPS_SRC_BYPASS_ASM

; =============================================================================
; File     : security/ips/src/bypass.asm
; Project  : Tattva OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: IPS Bypass - fail-open/fail-closed toggle for high-availability
;              paths. Critical infrastructure traffic can bypass enforcement
;              when components are unhealthy.
; Status   : PREMIUM SKELETON - bypass rules, fail-mode management defined.
; Logic bodies marked STUB.
; =============================================================================

bits 64
DEFAULT REL

%include "include/ips.inc"

section .bss
alignb 16
ips_bypass_state:       resb ips_state_base_t_size
ips_bypass_rule_head:   resq 1      ; bypass rule linked list
ips_bypass_rule_count:  resq 1
ips_bypass_fail_mode:   resd 1      ; current fail mode (IPS_FAIL_CLOSED/OPEN)

section .data
alignb 16
ips_bypass_version_str: db IPS_VERSION_STR, 0

section .text

; =============================================================================
; ips_bypass_init - Initialize bypass component
; Input:  none
; Output: rax = 0 on success, negative on failure
; =============================================================================
global ips_bypass_init
ips_bypass_init:
    push    rbx

    mov     dword [ips_bypass_state + ips_state_base_t.magic], IPS_STATE_MAGIC
    mov     dword [ips_bypass_state + ips_state_base_t.version], IPS_VERSION_MAJOR
    mov     byte [ips_bypass_state + ips_state_base_t.enabled], 1

    mov     qword [ips_bypass_rule_head], 0
    mov     qword [ips_bypass_rule_count], 0
    mov     dword [ips_bypass_fail_mode], IPS_FAIL_CLOSED   ; secure default

    ; STUB: allocate bypass rule memory pool
    ; STUB: load bypass rules from config (HA paths, critical infra)
    ; STUB: register health check callbacks

    xor     eax, eax
    pop     rbx
    ret

; =============================================================================
; ips_bypass_shutdown - Shut down bypass component
; Input:  none
; Output: rax = 0 on success
; =============================================================================
global ips_bypass_shutdown
ips_bypass_shutdown:
    push    rbx

    mov     eax, [ips_bypass_state + ips_state_base_t.magic]
    cmp     eax, IPS_STATE_MAGIC
    jnz     .not_init

    ; STUB: free all bypass rules

    mov     dword [ips_bypass_state + ips_state_base_t.magic], IPS_STATE_MAGIC_FREED
    mov     byte [ips_bypass_state + ips_state_base_t.enabled], 0

    xor     eax, eax
    pop     rbx
    ret
.not_init:
    mov     eax, -1
    pop     rbx
    ret

; =============================================================================
; ips_bypass_status - Return current bypass status
; Input:  none
; Output: rax = status code
; =============================================================================
global ips_bypass_status
ips_bypass_status:
    mov     eax, [ips_bypass_state + ips_state_base_t.magic]
    cmp     eax, IPS_STATE_MAGIC
    jnz     .not_init
    mov     al, [ips_bypass_state + ips_state_base_t.enabled]
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
; ips_bypass_version - Return version string pointer
; Input:  none
; Output: rax = pointer to NUL-terminated version string
; =============================================================================
global ips_bypass_version
ips_bypass_version:
    mov     rax, ips_bypass_version_str
    ret

; =============================================================================
; ips_bypass_check - Check if traffic should bypass enforcement
; Input:  rdi = enforce_ctx pointer (ips_enforce_ctx_t*)
; Output: rax = 1 if bypass (allow without enforcement), 0 if enforce normally
; =============================================================================
global ips_bypass_check
ips_bypass_check:
    push    rbx

    mov     eax, [ips_bypass_state + ips_state_base_t.magic]
    cmp     eax, IPS_STATE_MAGIC
    jnz     .err_component_down

    test    rdi, rdi
    jz      .err_invalid

    ; STUB: check if src/dst IP matches bypass rule
    ; STUB: if bypass rule matches and fail_mode = OPEN -> allow
    ; For skeleton: no bypass rules, enforce normally
    xor     eax, eax   ; 0 = enforce normally
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

; =============================================================================
; ips_bypass_set_fail_mode - Set system fail mode
; Input:  rdi = fail mode (IPS_FAIL_CLOSED or IPS_FAIL_OPEN)
; Output: rax = 0 on success, negative on failure
; =============================================================================
global ips_bypass_set_fail_mode
ips_bypass_set_fail_mode:
    push    rbx

    mov     eax, [ips_bypass_state + ips_state_base_t.magic]
    cmp     eax, IPS_STATE_MAGIC
    jnz     .err_component_down

    ; STUB: validate fail mode value
    ; STUB: update global fail mode in ips_global_state
    ; STUB: log fail mode change to audit

    mov     eax, 0
    pop     rbx
    ret

.err_component_down:
    mov     rax, -1
    pop     rbx
    ret

%endif
