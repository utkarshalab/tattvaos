%ifndef GUARD_SECURITY_IPS_SRC_SSL_TERMINATION_ASM
%define GUARD_SECURITY_IPS_SRC_SSL_TERMINATION_ASM

; =============================================================================
; File     : security/ips/src/ssl_termination.asm
; Project  : Tattva OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: IPS SSL Termination - terminates SSL/TLS connections at the
;              IPS layer for deep inspection, re-encrypts clean traffic,
;              and enforces TLS security policies.
; Status   : PREMIUM ENTERPRISE - full API surface, logic bodies marked STUB.
; =============================================================================

bits 64
DEFAULT REL

%include "include/ips.inc"

section .bss
alignb 16
ips_ssl_term_state:        resb ips_state_base_t_size
ips_ssl_term_session_head: resq 1
ips_ssl_term_session_count: resq 1

section .data
alignb 16
ips_ssl_term_version_str: db IPS_VERSION_STR, 0

section .text

; =============================================================================
; ips_ssl_termination_init - Initialize SSL termination
; Input:  none
; Output: rax = 0 on success, negative error code on failure
; =============================================================================
global ips_ssl_termination_init
ips_ssl_termination_init:
    push    rbx
    mov     dword [ips_ssl_term_state + ips_state_base_t.magic], IPS_STATE_MAGIC
    mov     dword [ips_ssl_term_state + ips_state_base_t.version], IPS_VERSION_MAJOR
    mov     byte [ips_ssl_term_state + ips_state_base_t.enabled], 1
    mov     qword [ips_ssl_term_session_head], 0
    mov     qword [ips_ssl_term_session_count], 0
    xor     eax, eax
    pop     rbx
    ret

; =============================================================================
; ips_ssl_termination_shutdown - Shut down SSL termination
; Input:  none
; Output: rax = 0 on success
; =============================================================================
global ips_ssl_termination_shutdown
ips_ssl_termination_shutdown:
    push    rbx
    mov     eax, [ips_ssl_term_state + ips_state_base_t.magic]
    cmp     eax, IPS_STATE_MAGIC
    jnz     .not_init
    mov     dword [ips_ssl_term_state + ips_state_base_t.magic], IPS_STATE_MAGIC_FREED
    mov     byte [ips_ssl_term_state + ips_state_base_t.enabled], 0
    xor     eax, eax
    pop     rbx
    ret
.not_init:
    mov     eax, -1
    pop     rbx
    ret

; =============================================================================
; ips_ssl_termination_status - Return current SSL termination status
; Input:  none
; Output: rax = status code
; =============================================================================
global ips_ssl_termination_status
ips_ssl_termination_status:
    mov     eax, [ips_ssl_term_state + ips_state_base_t.magic]
    cmp     eax, IPS_STATE_MAGIC
    jnz     .not_init
    mov     al, [ips_ssl_term_state + ips_state_base_t.enabled]
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
; ips_ssl_termination_version - Return version string pointer
; Input:  none
; Output: rax = pointer to NUL-terminated version string
; =============================================================================
global ips_ssl_termination_version
ips_ssl_termination_version:
    mov     rax, ips_ssl_term_version_str
    ret

; =============================================================================
; ips_ssl_terminate - Terminate SSL/TLS connection for inspection
; Input:  rdi = enforce context pointer, rsi = server cert pointer,
;         rdx = cert length, rcx = private key pointer
; Output: rax = 0 on success, negative error code on failure
; =============================================================================
global ips_ssl_terminate
ips_ssl_terminate:
    push    rbx
    push    r12

    mov     eax, [ips_ssl_term_state + ips_state_base_t.magic]
    cmp     eax, IPS_STATE_MAGIC
    jnz     .err_component_down

    test    rdi, rdi
    jz      .err_invalid_arg

    mov     r12, rdi              ; save enforce context pointer

    ; STUB: complete TLS handshake with client
    ; STEP: decrypt traffic for deep inspection
    ; STEP: enforce TLS version and cipher suite policies
    ; STEP: re-encrypt inspected traffic for forwarding
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

; STUB: ips_ssl_termination_add_cert - add server certificate
; STUB: ips_ssl_termination_remove_cert - remove server certificate
; STUB: ips_ssl_termination_list_sessions - list active TLS sessions
; STUB: ips_ssl_termination_get_stats - return termination statistics

%endif