%ifndef GUARD_SECURITY_IPS_SRC_CONNECTION_TERMINATOR_ASM
%define GUARD_SECURITY_IPS_SRC_CONNECTION_TERMINATOR_ASM

; =============================================================================
; File     : security/ips/src/connection_terminator.asm
; Project  : Utkarsha OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: IPS Connection Terminator - kills malicious TCP connections
;              by injecting RST packets, terminates UDP flows, and
;              enforces connection-level blocking.
; Status   : PREMIUM ENTERPRISE - full API surface, logic bodies marked STUB.
; =============================================================================

bits 64
DEFAULT REL

%include "include/ips.inc"

section .bss
alignb 16
ips_conn_term_state:       resb ips_state_base_t_size
ips_conn_term_kill_head:   resq 1
ips_conn_term_kill_count:  resq 1

section .data
alignb 16
ips_conn_term_version_str: db IPS_VERSION_STR, 0

section .text

; =============================================================================
; ips_connection_terminator_init - Initialize connection terminator
; Input:  none
; Output: rax = 0 on success, negative error code on failure
; =============================================================================
global ips_connection_terminator_init
ips_connection_terminator_init:
    push    rbx
    mov     dword [ips_conn_term_state + ips_state_base_t.magic], IPS_STATE_MAGIC
    mov     dword [ips_conn_term_state + ips_state_base_t.version], IPS_VERSION_MAJOR
    mov     byte [ips_conn_term_state + ips_state_base_t.enabled], 1
    mov     qword [ips_conn_term_kill_head], 0
    mov     qword [ips_conn_term_kill_count], 0
    xor     eax, eax
    pop     rbx
    ret

; =============================================================================
; ips_connection_terminator_shutdown - Shut down connection terminator
; Input:  none
; Output: rax = 0 on success
; =============================================================================
global ips_connection_terminator_shutdown
ips_connection_terminator_shutdown:
    push    rbx
    mov     eax, [ips_conn_term_state + ips_state_base_t.magic]
    cmp     eax, IPS_STATE_MAGIC
    jnz     .not_init
    mov     dword [ips_conn_term_state + ips_state_base_t.magic], IPS_STATE_MAGIC_FREED
    mov     byte [ips_conn_term_state + ips_state_base_t.enabled], 0
    xor     eax, eax
    pop     rbx
    ret
.not_init:
    mov     eax, -1
    pop     rbx
    ret

; =============================================================================
; ips_connection_terminator_status - Return current connection terminator status
; Input:  none
; Output: rax = status code
; =============================================================================
global ips_connection_terminator_status
ips_connection_terminator_status:
    mov     eax, [ips_conn_term_state + ips_state_base_t.magic]
    cmp     eax, IPS_STATE_MAGIC
    jnz     .not_init
    mov     al, [ips_conn_term_state + ips_state_base_t.enabled]
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
; ips_connection_terminator_version - Return version string pointer
; Input:  none
; Output: rax = pointer to NUL-terminated version string
; =============================================================================
global ips_connection_terminator_version
ips_connection_terminator_version:
    mov     rax, ips_conn_term_version_str
    ret

; =============================================================================
; ips_connection_terminate - Terminate a malicious connection
; Input:  rdi = enforce context pointer, rsi = src IP,
;         rdx = dst IP, rcx = src/dst ports
; Output: rax = 0 on success, negative error code on failure
; =============================================================================
global ips_connection_terminate
ips_connection_terminate:
    push    rbx
    push    r12

    mov     eax, [ips_conn_term_state + ips_state_base_t.magic]
    cmp     eax, IPS_STATE_MAGIC
    jnz     .err_component_down

    test    rdi, rdi
    jz      .err_invalid_arg

    mov     r12, rdi              ; save enforce context pointer

    ; STUB: inject TCP RST packet to both endpoints
    ; STEP: terminate UDP flow by sending ICMP unreachable
    ; STEP: record connection termination in audit log
    ; STEP: update connection tracker state
    ; STEP: return success

    xor     eax, eax
    jmp     .done

.err_component_down:
    mov     rax, -1
    jmp     .done
.err_invalid_arg:
    mov     rax, -2
    jmp     .done

.done:
    pop     r12
    pop     rbx
    ret

; STUB: ips_connection_terminator_list_kills - list terminated connections
; STUB: ips_connection_terminator_clear_kills - clear termination records
; STUB: ips_connection_terminator_get_stats - return termination statistics

%endif