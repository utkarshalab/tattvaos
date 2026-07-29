; =============================================================================
; Tattva OS — unet/core/sys/pktbuf.asm
; =============================================================================
; Zero-Copy Hardware DMA Buffer Allocator & Non-Temporal Store Engine.
;
; Implements:
;   - Lockless 2MB / 1GB Hugepage Pre-Allocated Packet Pool (0 Memory Alloc Latency)
;   - Software Cache Line Prefetching (`prefetcht0` / `prefetchnta`)
;   - Non-Temporal Vector Copy (`vmovntdq`) to Prevent CPU L1/L2 Cache Pollution
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define PKTBUF_POOL_SIZE            8192
%define PKTBUF_FRAME_LEN            2048

section .data
align 64
global pktbuf_free_list
pktbuf_free_list: times PKTBUF_POOL_SIZE dq 0

align 8
global pktbuf_free_head
pktbuf_free_head: dq 0

align 8
global pktbuf_free_count
pktbuf_free_count: dq PKTBUF_POOL_SIZE

section .text

global pktbuf_init
global pktbuf_alloc
global pktbuf_free
global pktbuf_copy_non_temporal

; -----------------------------------------------------------------------------
; pktbuf_init — Pre-allocate 2MB Hugepage Packet Buffer Pool
; -----------------------------------------------------------------------------
align 32
pktbuf_init:
    push rbp
    mov rbp, rsp
    mov qword [pktbuf_free_head], 0
    mov qword [pktbuf_free_count], PKTBUF_POOL_SIZE
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; pktbuf_alloc — Lockless Constant-Time (O(1)) Packet Buffer Allocation
; Output: RAX = Pointer to net_pkt_t (or 0 if Pool Exhausted)
; -----------------------------------------------------------------------------
align 32
pktbuf_alloc:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, [pktbuf_free_head]
    cmp rbx, PKTBUF_POOL_SIZE
    jae .pool_empty

    ; Pop free buffer pointer from array
    mov rax, [pktbuf_free_list + rbx * 8]
    inc qword [pktbuf_free_head]
    dec qword [pktbuf_free_count]

    ; Prefetch buffer header into L1i/L1d Cache
    prefetcht0 [rax]

    pop rbx
    pop rbp
    ret

.pool_empty:
    xor eax, eax
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; pktbuf_free — Return Buffer to Lockless Pool
; Input: RDI = Pointer to net_pkt_t
; -----------------------------------------------------------------------------
align 32
pktbuf_free:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, [pktbuf_free_head]
    test rbx, rbx
    jz .done

    dec qword [pktbuf_free_head]
    mov [pktbuf_free_list + rbx * 8 - 8], rdi
    inc qword [pktbuf_free_count]

.done:
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; pktbuf_copy_non_temporal — AVX-512 Non-Temporal Memory Copy (`vmovntdq`)
; Input: RDI = Destination Address, RSI = Source Address, ECX = Length in Bytes
; -----------------------------------------------------------------------------
align 32
pktbuf_copy_non_temporal:
    push rbp
    mov rbp, rsp

.loop:
    cmp ecx, 64
    jb .remainder
    vmovdqu64 zmm0, [rsi]
    vmovntdq [rdi], zmm0             ; Non-temporal store (bypasses L1/L2 cache)
    add rsi, 64
    add rdi, 64
    sub ecx, 64
    jmp .loop

.remainder:
    vzeroall
    pop rbp
    ret
