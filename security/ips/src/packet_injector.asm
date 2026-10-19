%ifndef GUARD_SECURITY_IPS_SRC_PACKET_INJECTOR_ASM
%define GUARD_SECURITY_IPS_SRC_PACKET_INJECTOR_ASM

; =============================================================================
; File     : security/ips/src/packet_injector.asm
; Project  : Tattva OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: IPS Packet Injector - injects custom packets (TCP RST,
;              ICMP unreachable, DNS redirect) into traffic flow for
;              active defense and connection manipulation.
; Status   : PREMIUM ENTERPRISE - full API surface, logic bodies marked STUB.
; =============================================================================

bits 64
DEFAULT REL

%include "include/ips.inc"

section .bss
alignb 16
ips_packet_inject_state:   resb ips_state_base_t_size
ips_packet_inject_rule_head: resq 1
ips_packet_inject_rule_count: resq 1

section .data
alignb 16
ips_packet_inject_version_str: db IPS_VERSION_STR, 0

section .text

; =============================================================================
; ips_packet_injector_init - Initialize packet injector
; Input:  none
; Output: rax = 0 on success, negative error code on failure
; =============================================================================
global ips_packet_injector_init
ips_packet_injector_init:
    push    rbx
    mov     dword [ips_packet_inject_state + ips_state_base_t.magic], IPS_STATE_MAGIC
    mov     dword [ips_packet_inject_state + ips_state_base_t.version], IPS_VERSION_MAJOR
    mov     byte [ips_packet_inject_state + ips_state_base_t.enabled], 1
    mov     qword [ips_packet_inject_rule_head], 0
    mov     qword [ips_packet_inject_rule_count], 0
    xor     eax, eax
    pop     rbx
    ret

; =============================================================================
; ips_packet_injector_shutdown - Shut down packet injector
; Input:  none
; Output: rax = 0 on success
; =============================================================================
global ips_packet_injector_shutdown
ips_packet_injector_shutdown:
    push    rbx
    mov     eax, [ips_packet_inject_state + ips_state_base_t.magic]
    cmp     eax, IPS_STATE_MAGIC
    jnz     .not_init
    mov     dword [ips_packet_inject_state + ips_state_base_t.magic], IPS_STATE_MAGIC_FREED
    mov     byte [ips_packet_inject_state + ips_state_base_t.enabled], 0
    xor     eax, eax
    pop     rbx
    ret
.not_init:
    mov     eax, -1
    pop     rbx
    ret

; =============================================================================
; ips_packet_injector_status - Return current packet injector status
; Input:  none
; Output: rax = status code
; =============================================================================
global ips_packet_injector_status
ips_packet_injector_status:
    mov     eax, [ips_packet_inject_state + ips_state_base_t.magic]
    cmp     eax, IPS_STATE_MAGIC
    jnz     .not_init
    mov     al, [ips_packet_inject_state + ips_state_base_t.enabled]
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
; ips_packet_injector_version - Return version string pointer
; Input:  none
; Output: rax = pointer to NUL-terminated version string
; =============================================================================
global ips_packet_injector_version
ips_packet_injector_version:
    mov     rax, ips_packet_inject_version_str
    ret

; =============================================================================
; ips_packet_inject - Inject a custom packet into traffic flow
; Input:  rdi = enforce context pointer, rsi = packet type,
;         rdx = target IP, rcx = payload pointer
; Output: rax = 0 on success, negative error code on failure
; =============================================================================
global ips_packet_inject
ips_packet_inject:
    push    rbx
    push    r12

    mov     eax, [ips_packet_inject_state + ips_state_base_t.magic]
    cmp     eax, IPS_STATE_MAGIC
    jnz     .err_component_down

    test    rdi, rdi
    jz      .err_invalid_arg

    mov     r12, rdi              ; save enforce context pointer

    ; STUB: construct packet (TCP RST, ICMP unreachable, DNS redirect)
    ; STEP: set source/destination IP and ports
    ; STEP: compute checksums and validate packet integrity
    ; STEP: inject packet into outbound interface
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

; STUB: ips_packet_injector_add_rule - add injection rule
; STUB: ips_packet_injector_remove_rule - remove injection rule
; STUB: ips_packet_injector_list_rules - list all injection rules
; STUB: ips_packet_injector_get_stats - return injection statistics

%endif