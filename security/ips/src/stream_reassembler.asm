%ifndef GUARD_SECURITY_IPS_SRC_STREAM_REASSEMBLER_ASM
%define GUARD_SECURITY_IPS_SRC_STREAM_REASSEMBLER_ASM

; =============================================================================
; File     : security/ips/src/stream_reassembler.asm
; Project  : Tattva OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: IPS Stream Reassembler - TCP stream reassembly engine that
;              reorders out-of-order segments, handles retransmissions,
;              and presents unified byte streams for inspection.
; Status   : PREMIUM ENTERPRISE - full API surface, logic bodies marked STUB.
; =============================================================================

bits 64
DEFAULT REL

%include "include/ips.inc"

section .bss
alignb 16
ips_stream_state:        resb ips_state_base_t_size
ips_stream_connection_head: resq 1
ips_stream_connection_count: resq 1

section .data
alignb 16
ips_stream_version_str: db IPS_VERSION_STR, 0

section .text

; =============================================================================
; ips_stream_reassembler_init - Initialize stream reassembler
; Input:  none
; Output: rax = 0 on success, negative error code on failure
; =============================================================================
global ips_stream_reassembler_init
ips_stream_reassembler_init:
    push    rbx
    mov     dword [ips_stream_state + ips_state_base_t.magic], IPS_STATE_MAGIC
    mov     dword [ips_stream_state + ips_state_base_t.version], IPS_VERSION_MAJOR
    mov     byte [ips_stream_state + ips_state_base_t.enabled], 1
    mov     qword [ips_stream_connection_head], 0
    mov     qword [ips_stream_connection_count], 0
    xor     eax, eax
    pop     rbx
    ret

; =============================================================================
; ips_stream_reassembler_shutdown - Shut down stream reassembler
; Input:  none
; Output: rax = 0 on success
; =============================================================================
global ips_stream_reassembler_shutdown
ips_stream_reassembler_shutdown:
    push    rbx
    mov     eax, [ips_stream_state + ips_state_base_t.magic]
    cmp     eax, IPS_STATE_MAGIC
    jnz     .not_init
    mov     dword [ips_stream_state + ips_state_base_t.magic], IPS_STATE_MAGIC_FREED
    mov     byte [ips_stream_state + ips_state_base_t.enabled], 0
    xor     eax, eax
    pop     rbx
    ret
.not_init:
    mov     eax, -1
    pop     rbx
    ret

; =============================================================================
; ips_stream_reassembler_status - Return current stream reassembler status
; Input:  none
; Output: rax = status code
; =============================================================================
global ips_stream_reassembler_status
ips_stream_reassembler_status:
    mov     eax, [ips_stream_state + ips_state_base_t.magic]
    cmp     eax, IPS_STATE_MAGIC
    jnz     .not_init
    mov     al, [ips_stream_state + ips_state_base_t.enabled]
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
; ips_stream_reassembler_version - Return version string pointer
; Input:  none
; Output: rax = pointer to NUL-terminated version string
; =============================================================================
global ips_stream_reassembler_version
ips_stream_reassembler_version:
    mov     rax, ips_stream_version_str
    ret

; =============================================================================
; ips_stream_reassemble - Reassemble TCP stream segments
; Input:  rdi = enforce context pointer, rsi = segment pointer,
;         rdx = segment length, rcx = sequence number
; Output: rax = reassembled byte count, rbx = connection state flag
; =============================================================================
global ips_stream_reassemble
ips_stream_reassemble:
    push    rbx
    push    r12

    mov     eax, [ips_stream_state + ips_state_base_t.magic]
    cmp     eax, IPS_STATE_MAGIC
    jnz     .err_component_down

    test    rdi, rdi
    jz      .err_invalid_arg

    mov     r12, rdi              ; save enforce context pointer

    ; STUB: place segment in reassembly buffer by sequence number
    ; STEP: handle out-of-order delivery and retransmissions
    ; STEP: detect stream desynchronization attacks
    ; STEP: return contiguous byte stream for inspection
    ; STEP: return reassembled byte count and connection state

    xor     eax, eax               ; STUB: no bytes reassembled
    xor     rbx, rbx               ; connection state unknown
    jmp     .done

.err_component_down:
    mov     rax, -1
    xor     rbx, rbx
    jmp     .done
.err_invalid_arg:
    mov     rax, -2
    xor     rbx, rbx
    jmp     .done

.done:
    pop     r12
    pop     rbx
    ret

; STUB: ips_stream_reassembler_get_stream - get reassembled stream
; STUB: ips_stream_reassembler_close_stream - close and cleanup stream
; STUB: ips_stream_reassembler_list_connections - list active connections
; STUB: ips_stream_reassembler_get_stats - return reassembly statistics

%endif