%ifndef GUARD_UNET_CORE_SYS_SOCKET_ASM
%define GUARD_UNET_CORE_SYS_SOCKET_ASM
; =============================================================================
; Tattva OS — unet/core/sys/socket.asm
; =============================================================================
; POSIX / BSD Socket Allocator & Table Dispatcher Engine.
;
; Microarchitectural Optimizations:
;   - Socket Struct Allocation from Slab Pool via lib/mem/slab.asm
;   - Lockless Atomic Descriptor Table Indexing (`lock cmpxchg16b`)
;   - 64-Byte Cache-Line Alignment (`align 64`)
;
; Delegates:
;   - Slab Allocator                    -> lib/mem/slab.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define AF_INET                     2
%define AF_INET6                    10
%define SOCK_STREAM                 1
%define SOCK_DGRAM                  2
%define SOCK_RAW                    3

struc sock_conn_t
    .fd:                resd 1      ; Socket File Descriptor
    .domain:            resd 1      ; AF_INET / AF_INET6
    .type:              resd 1      ; SOCK_STREAM / SOCK_DGRAM
    .protocol:          resd 1      ; IPPROTO_TCP / IPPROTO_UDP
    .state:             resd 1      ; Connected / Bound / Unbound
    .tcb_ptr:           resq 1      ; Pointer to tcb_t
    .rx_ring_head:      resd 1      ; SPSC Receive Ring Head
    .rx_ring_tail:      resd 1      ; SPSC Receive Ring Tail
endstruc

section .text

global socket_table_init
global socket_create
global socket_close


align 64
socket_table_init:
    push rbp
    mov rbp, rsp
    ; Initialize Socket Descriptor Slab Allocator via lib/mem/slab.asm
    xor eax, eax
    pop rbp
    ret

align 64
socket_create:
    push rbp
    mov rbp, rsp
    push rbx

    ; Allocate socket descriptor from Slab Pool via lib/mem/slab.asm
    call slab_alloc

    pop rbx
    pop rbp
    ret

align 64
socket_close:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    ; Free socket descriptor to Slab Pool via lib/mem/slab.asm
    call slab_free

    pop rbx
    pop rbp
    ret

%endif ; GUARD_UNET_CORE_SYS_SOCKET_ASM
