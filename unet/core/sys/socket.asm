; =============================================================================
; Tattva OS — unet/core/sys/socket.asm
; =============================================================================
; BSD Socket API Subsystem (Delegated to lib/mem/slab.asm).
;
; Delegates:
;   - Socket Handle Allocation  -> lib/mem/slab.asm (`slab_alloc`, `slab_free`)
;   - Socket Shared Ring Buffers -> unet/core/link/sbuf.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

struc socket_t
    .fd:                resd 1      ; Socket Descriptor ID
    .domain:            resd 1      ; AF_INET (2) / AF_INET6 (10)
    .type:              resd 1      ; SOCK_STREAM (1) / SOCK_DGRAM (2)
    .protocol:          resd 1      ; IPPROTO_TCP (6) / IPPROTO_UDP (17)
    .state:             resd 1      ; Socket State
    .rx_ring:           resq 1      ; Pointer to sbuf_t RX ring
    .tx_ring:           resq 1      ; Pointer to sbuf_t TX ring
endstruc

section .text

global sys_socket
global sys_bind
global sys_listen
global sys_accept
global sys_connect

extern slab_alloc
extern slab_free

; -----------------------------------------------------------------------------
; sys_socket — Allocate Socket Descriptor via lib/mem/slab.asm
; Input: EDI = Domain, ESI = Type, EDX = Protocol
; Output: RAX = Socket FD (or negative error)
; -----------------------------------------------------------------------------
align 32
sys_socket:
    push rbp
    mov rbp, rsp

    ; Allocate socket_t object from slab allocator
    mov rdi, socket_t_size
    call slab_alloc

    pop rbp
    ret

align 32
sys_bind:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
sys_listen:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
sys_accept:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
sys_connect:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret
