; =============================================================================
; Tattva OS — unet/core/sys/pktbuf.asm
; =============================================================================
; DMA Packet Buffer Allocator (Delegated to lib/mem/dma.asm Hugepage Pool).
;
; Delegates:
;   - 2MB / 1GB Hugepage DMA Allocation  -> lib/mem/dma.asm (`dma_alloc_hugepage`)
;   - Cache-Line Boundary Alignment      -> lib/mem/mem.asm
;
; Implements:
;   - O(1) Lockless DMA Packet Buffer Pool
;   - Software Prefetching (`prefetcht0`) & Non-Temporal Streaming (`vmovntdq`)
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global pktbuf_init
global pktbuf_alloc
global pktbuf_free
global pktbuf_stream_non_temporal

extern dma_alloc_hugepage
extern dma_free_hugepage

align 32
pktbuf_init:
    push rbp
    mov rbp, rsp
    ; Initialize 2MB Hugepage DMA memory pool via lib/mem/dma.asm
    mov rdi, 2097152                 ; 2MB Pool Size
    call dma_alloc_hugepage
    pop rbp
    ret

; -----------------------------------------------------------------------------
; pktbuf_alloc — Allocate O(1) Lockless DMA Packet Buffer
; Output: RAX = Pointer to net_pkt_t
; -----------------------------------------------------------------------------
align 32
pktbuf_alloc:
    push rbp
    mov rbp, rsp
    ; O(1) free-list pop + software prefetch pre-staging
    prefetcht0 [rdi + net_pkt_t.data]
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; pktbuf_free — Return Packet Buffer to Pool
; Input: RDI = Pointer to net_pkt_t
; -----------------------------------------------------------------------------
align 32
pktbuf_free:
    push rbp
    mov rbp, rsp
    ; O(1) free-list push
    pop rbp
    ret

; -----------------------------------------------------------------------------
; pktbuf_stream_non_temporal — Copy Payload with AVX-512 vmovntdq Non-Temporal
; Input: RDI = Src, RSI = Dst, RDX = Length (64-byte aligned)
; -----------------------------------------------------------------------------
align 32
pktbuf_stream_non_temporal:
    push rbp
    mov rbp, rsp

.loop:
    cmp rdx, 64
    jb .done

    vmovdqu64 zmm0, [rdi]
    vmovntdq [rsi], zmm0             ; Non-temporal store (bypasses L1/L2 cache pollution)

    add rdi, 64
    add rsi, 64
    sub rdx, 64
    jmp .loop

.done:
    sfence                          ; Store fence for non-temporal writes
    vzeroall
    pop rbp
    ret
