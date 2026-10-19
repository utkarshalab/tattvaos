%ifndef GUARD_SECURITY_IPS_SRC_LOAD_BALANCER_INTEGRATION_ASM
%define GUARD_SECURITY_IPS_SRC_LOAD_BALANCER_INTEGRATION_ASM

; =============================================================================
; File     : security/ips/src/load_balancer_integration.asm
; Project  : Tattva OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: IPS Load Balancer Integration - integrates with load balancers
;              to drain compromised backends, redirect traffic to healthy
;              endpoints, and enforce security policies at the LB layer.
; Status   : PREMIUM ENTERPRISE - full API surface, logic bodies marked STUB.
; =============================================================================

bits 64
DEFAULT REL

%include "include/ips.inc"

section .bss
alignb 16
ips_lb_state:              resb ips_state_base_t_size
ips_lb_backend_head:       resq 1
ips_lb_backend_count:      resq 1

section .data
alignb 16
ips_lb_version_str: db IPS_VERSION_STR, 0

section .text

; =============================================================================
; ips_load_balancer_integration_init - Initialize load balancer integration
; Input:  none
; Output: rax = 0 on success, negative error code on failure
; =============================================================================
global ips_load_balancer_integration_init
ips_load_balancer_integration_init:
    push    rbx
    mov     dword [ips_lb_state + ips_state_base_t.magic], IPS_STATE_MAGIC
    mov     dword [ips_lb_state + ips_state_base_t.version], IPS_VERSION_MAJOR
    mov     byte [ips_lb_state + ips_state_base_t.enabled], 1
    mov     qword [ips_lb_backend_head], 0
    mov     qword [ips_lb_backend_count], 0
    xor     eax, eax
    pop     rbx
    ret

; =============================================================================
; ips_load_balancer_integration_shutdown - Shut down load balancer integration
; Input:  none
; Output: rax = 0 on success
; =============================================================================
global ips_load_balancer_integration_shutdown
ips_load_balancer_integration_shutdown:
    push    rbx
    mov     eax, [ips_lb_state + ips_state_base_t.magic]
    cmp     eax, IPS_STATE_MAGIC
    jnz     .not_init
    mov     dword [ips_lb_state + ips_state_base_t.magic], IPS_STATE_MAGIC_FREED
    mov     byte [ips_lb_state + ips_state_base_t.enabled], 0
    xor     eax, eax
    pop     rbx
    ret
.not_init:
    mov     eax, -1
    pop     rbx
    ret

; =============================================================================
; ips_load_balancer_integration_status - Return current load balancer integration status
; Input:  none
; Output: rax = status code
; =============================================================================
global ips_load_balancer_integration_status
ips_load_balancer_integration_status:
    mov     eax, [ips_lb_state + ips_state_base_t.magic]
    cmp     eax, IPS_STATE_MAGIC
    jnz     .not_init
    mov     al, [ips_lb_state + ips_state_base_t.enabled]
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
; ips_load_balancer_integration_version - Return version string pointer
; Input:  none
; Output: rax = pointer to NUL-terminated version string
; =============================================================================
global ips_load_balancer_integration_version
ips_load_balancer_integration_version:
    mov     rax, ips_lb_version_str
    ret

; =============================================================================
; ips_load_balancer_drain_backend - Drain a compromised backend from LB
; Input:  rdi = backend context pointer, rsi = backend IP,
;         rdx = backend port, rcx = drain duration_ms
; Output: rax = 0 on success, negative error code on failure
; =============================================================================
global ips_load_balancer_drain_backend
ips_load_balancer_drain_backend:
    push    rbx
    push    r12

    mov     eax, [ips_lb_state + ips_state_base_t.magic]
    cmp     eax, IPS_STATE_MAGIC
    jnz     .err_component_down

    test    rdi, rdi
    jz      .err_invalid_arg

    mov     r12, rdi              ; save backend context pointer

    ; STUB: mark backend as draining in load balancer
    ; STEP: stop sending new connections to backend
    ; STEP: allow existing connections to complete
    ; STEP: redirect new traffic to healthy backends
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

; STUB: ips_load_balancer_add_backend - add backend to LB pool
; STUB: ips_load_balancer_remove_backend - remove backend from LB pool
; STUB: ips_load_balancer_list_backends - list all backends
; STUB: ips_load_balancer_get_stats - return integration statistics

%endif