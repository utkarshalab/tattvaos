%ifndef GUARD_SECURITY_INCIDENT_RESPONSE_CONTAINMENT_ASM
%define GUARD_SECURITY_INCIDENT_RESPONSE_CONTAINMENT_ASM

; =============================================================================
; File     : security/incident_response/src/containment.asm
; Project  : Utkarsha OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: IR containment (isolate hosts, revoke sessions, block indicators)
; Status   : PREMIUM ENTERPRISE - skeleton with full API surface.
; =============================================================================

bits 64
DEFAULT REL

%include "include/ir.inc"

section .bss
alignb 16
ir_containment_state:     resb ir_state_base_t_size
ir_containment_action_head: resq 1
ir_containment_action_count: resq 1

section .data
alignb 16
ir_containment_version_str: db IR_VERSION_STR, 0

section .text

; =============================================================================
; ir_containment_init - Initialize IR containment
; Input:  none
; Output: rax = 0 on success, negative error code on failure
; =============================================================================
global ir_containment_init
ir_containment_init:
    push    rbx
    mov     dword [ir_containment_state + ir_state_base_t.magic], IR_STATE_MAGIC
    mov     dword [ir_containment_state + ir_state_base_t.version], IR_VERSION_MAJOR
    mov     byte [ir_containment_state + ir_state_base_t.enabled], 1
    mov     qword [ir_containment_action_head], 0
    mov     qword [ir_containment_action_count], 0
    xor     eax, eax
    pop     rbx
    ret

; =============================================================================
; ir_containment_shutdown - Shut down IR containment
; Input:  none
; Output: rax = 0 on success
; =============================================================================
global ir_containment_shutdown
ir_containment_shutdown:
    push    rbx
    mov     eax, [ir_containment_state + ir_state_base_t.magic]
    cmp     eax, IR_STATE_MAGIC
    jnz     .not_init
    mov     dword [ir_containment_state + ir_state_base_t.magic], IR_STATE_MAGIC_FREED
    mov     byte [ir_containment_state + ir_state_base_t.enabled], 0
    xor     eax, eax
    pop     rbx
    ret
.not_init:
    mov     eax, -1
    pop     rbx
    ret

; =============================================================================
; ir_containment_status - Return current IR containment status
; Input:  none
; Output: rax = status code
; =============================================================================
global ir_containment_status
ir_containment_status:
    mov     eax, [ir_containment_state + ir_state_base_t.magic]
    cmp     eax, IR_STATE_MAGIC
    jnz     .not_init
    mov     al, [ir_containment_state + ir_state_base_t.enabled]
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
; ir_containment_version - Return version string pointer
; Input:  none
; Output: rax = pointer to NUL-terminated version string
; =============================================================================
global ir_containment_version
ir_containment_version:
    mov     rax, ir_containment_version_str
    ret

; =============================================================================
; ir_containment_isolate_host - Isolate a host from the network
; Input:  rdi = incident ID, rsi = host identifier pointer
; Output: rax = action ID on success, negative error code on failure
; =============================================================================
global ir_containment_isolate_host
ir_containment_isolate_host:
    push    rbx
    push    r12

    mov     eax, [ir_containment_state + ir_state_base_t.magic]
    cmp     eax, IR_STATE_MAGIC
    jnz     .err_not_init

    test    rsi, rsi
    jz      .err_invalid_arg

    mov     r12, rsi              ; save host identifier

    ; STUB: validate incident ID exists and is triaged
    ; STUB: create containment action record (IR_CONTAIN_ISOLATE_HOST)
    ; STEP: execute network isolation (firewall rule, NAC, etc.)
    ; STEP: verify host is isolated
    ; STEP: update incident status to CONTAINED

    mov     rax, 1               ; STUB: return action ID 1
    jmp     .done

.err_not_init:
    mov     rax, IR_ERR_NOT_INIT
    jmp     .done
.err_invalid_arg:
    mov     rax, IR_ERR_INVALID_ARG
    jmp     .done

.done:
    pop     r12
    pop     rbx
    ret

; =============================================================================
; ir_containment_revoke_session - Revoke a user/session
; Input:  rdi = incident ID, rsi = session identifier pointer
; Output: rax = action ID on success, negative error code on failure
; =============================================================================
global ir_containment_revoke_session
ir_containment_revoke_session:
    push    rbx

    mov     eax, [ir_containment_state + ir_state_base_t.magic]
    cmp     eax, IR_STATE_MAGIC
    jnz     .err_not_init

    ; STUB: validate incident ID exists
    ; STUB: create containment action record (IR_CONTAIN_REVOKE_SESSION)
    ; STEP: revoke session via identity provider
    ; STEP: verify session is revoked

    mov     rax, 2               ; STUB: return action ID 2
    pop     rbx
    ret

.err_not_init:
    mov     rax, IR_ERR_NOT_INIT
    pop     rbx
    ret

; =============================================================================
; ir_containment_block_indicator - Block an indicator (IP, domain, hash)
; Input:  rdi = incident ID, rsi = indicator pointer,
;         rdx = indicator length
; Output: rax = action ID on success, negative error code on failure
; =============================================================================
global ir_containment_block_indicator
ir_containment_block_indicator:
    push    rbx

    mov     eax, [ir_containment_state + ir_state_base_t.magic]
    cmp     eax, IR_STATE_MAGIC
    jnz     .err_not_init

    ; STUB: validate incident ID exists
    ; STUB: create containment action record (IR_CONTAIN_BLOCK_INDICATOR)
    ; STEP: add indicator to blocklist (firewall, proxy, EDR)
    ; STEP: verify indicator is blocked

    mov     rax, 3               ; STUB: return action ID 3
    pop     rbx
    ret

.err_not_init:
    mov     rax, IR_ERR_NOT_INIT
    pop     rbx
    ret

; STUB: ir_containment_disable_account - disable a user account
; STUB: ir_containment_disable_service - disable a network service
; STUB: ir_containment_get_actions - list containment actions for incident
; STUB: ir_containment_verify_action - verify containment action effectiveness
; STUB: ir_containment_lift_containment - lift containment after remediation
; STUB: ir_containment_get_stats - return containment statistics

%endif