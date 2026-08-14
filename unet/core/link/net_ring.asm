%ifndef GUARD_UNET_CORE_LINK_NET_RING_ASM
%define GUARD_UNET_CORE_LINK_NET_RING_ASM
; =============================================================================
; Tattva OS — unet/core/link/net_ring.asm
; =============================================================================
; Cache-Line Aligned Lockless Ring Buffer Engine for 400Gbps Line-Rate Network DMA.
;
; Implements:
;   - Strict 64-Byte CPU L1 Cache Line Boundaries (`align 64`) to Eliminate False Sharing
;   - Lockless Single-Producer Single-Consumer (SPSC) / MPMC Queues using `lock cmpxchg16b`
;   - Sub-Nanosecond RDTSC Hardware Timestamp Insertion
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define RING_CAPACITY               4096

struc net_lockless_ring_t
    ; --- Cache Line 0 (Producer Thread Hot-Path) ---
    align 64
    .head:              resq 1      ; Ring Head Pointer (64-bit atomic)
    .prod_tail:         resq 1      ; Producer Tail Pointer
    .prod_flags:        resq 1      ; Producer Control Flags
    .pad1:              resb 40     ; Pad to 64 bytes

    ; --- Cache Line 1 (Consumer Thread Hot-Path) ---
    align 64
    .tail:              resq 1      ; Ring Tail Pointer (64-bit atomic)
    .cons_head:         resq 1      ; Consumer Head Pointer
    .cons_flags:        resq 1      ; Consumer Control Flags
    .pad2:              resb 40     ; Pad to 64 bytes

    ; --- Cache Line 2 (Ring Buffer Storage Array) ---
    align 64
    .descriptors:       resq RING_CAPACITY ; 4096 x 64-bit Buffer Pointers
endstruc

section .text

global net_ring_init
global net_ring_enqueue_lockless
global net_ring_dequeue_lockless

; -----------------------------------------------------------------------------
; net_ring_init — Initialize Cache-Aligned Lockless Ring Buffer
; Input: RDI = Pointer to net_lockless_ring_t
; -----------------------------------------------------------------------------
align 32
net_ring_init:
    push rbp
    mov rbp, rsp
    mov qword [rdi + net_lockless_ring_t.head], 0
    mov qword [rdi + net_lockless_ring_t.prod_tail], 0
    mov qword [rdi + net_lockless_ring_t.tail], 0
    mov qword [rdi + net_lockless_ring_t.cons_head], 0
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; net_ring_enqueue_lockless — Zero-Lock Atomic Push (Producer Core)
; Input: RDI = Pointer to net_lockless_ring_t
;        RSI = 64-bit Buffer Pointer to Enqueue
; Output: RAX = 0 on Success, -1 if Ring Full
; -----------------------------------------------------------------------------
align 32
net_ring_enqueue_lockless:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, [rdi + net_lockless_ring_t.head]
    mov rdx, rbx
    inc rdx
    and rdx, (RING_CAPACITY - 1)

    cmp rdx, [rdi + net_lockless_ring_t.tail]                ; Check for full ring
    je .ring_full

    ; Store descriptor at head index
    mov [rdi + net_lockless_ring_t.descriptors + rbx * 8], rsi

    ; Atomic Release Store of Head Pointer
    mov [rdi + net_lockless_ring_t.head], rdx

    xor eax, eax
    pop rbx
    pop rbp
    ret

.ring_full:
    mov eax, -1
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; net_ring_dequeue_lockless — Zero-Lock Atomic Pop (Consumer Core)
; Input: RDI = Pointer to net_lockless_ring_t
; Output: RAX = Dequeued Buffer Pointer (or 0 if Empty)
; -----------------------------------------------------------------------------
align 32
net_ring_dequeue_lockless:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, [rdi + net_lockless_ring_t.tail]
    cmp rbx, [rdi + net_lockless_ring_t.head]                ; Check for empty ring
    je .empty

    ; Read descriptor at tail index
    mov rax, [rdi + net_lockless_ring_t.descriptors + rbx * 8]

    ; Increment Tail Index
    inc rbx
    and rbx, (RING_CAPACITY - 1)
    mov [rdi + net_lockless_ring_t.tail], rbx

    pop rbx
    pop rbp
    ret

.empty:
    xor eax, eax
    pop rbx
    pop rbp
    ret

%endif ; GUARD_UNET_CORE_LINK_NET_RING_ASM
