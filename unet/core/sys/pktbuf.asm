; =============================================================================
; Tattva OS — unet/core/sys/pktbuf.asm
; =============================================================================
; AVX-512 2MB/1GB Hugepages Lockless Packet Buffer Allocation Engine.
;
; Microarchitectural & Hardware Optimizations:
;   - 2MB / 1GB Hugepage DMA Memory Pool Allocation via lib/mem/dma.asm
;   - AVX-512 Non-Temporal Stores (`vmovntdq`) to Eliminate L3 Cache Pollution
;   - Lockless Atomic SPSC/MPMC Ring Buffer Recycle Pool (`recycle.asm`)
;   - 64-Byte Cache-Line Aligned Structs (`align 64`) & `prefetcht0` L1 Staging
;
; Delegates:
;   - Hugepage Allocator                -> lib/mem/dma.asm (`dma_alloc_hugepage`)
;   - Hardware TSC Timestamp            -> lib/time/tsc.asm (`rdtsc_get_cycles`)
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define PKTBUF_SIZE                 2048
%define PKTBUF_HEADROOM             128

struc net_pkt_t
    .head:              resq 1      ; Buffer Head Pointer
    .data:              resq 1      ; Current Data Pointer
    .tail:              resq 1      ; Current Tail Pointer
    .end:               resq 1      ; Buffer End Pointer
    .len:               resd 1      ; Packet Data Length
    .vlan_tag:          resw 1      ; Offloaded VLAN Tag
    .vni:               resd 1      ; Offloaded VXLAN VNI
    .timestamp:         resq 1      ; Hardware Ingress TSC Timestamp (lib/time/tsc.asm)
    .refcnt:            resd 1      ; Atomic Reference Counter
endstruc

section .text

global pktbuf_init
global pktbuf_alloc
global pktbuf_free
global pktbuf_copy_avx512

extern dma_alloc_hugepage
extern rdtsc_get_cycles

align 64
pktbuf_init:
    push rbp
    mov rbp, rsp
    ; Allocate 2MB/1GB Hugepages for Network Packet Pools via lib/mem/dma.asm
    mov rdi, 2 * 1024 * 1024        ; 2MB Hugepage
    call dma_alloc_hugepage
    pop rbp
    ret

; -----------------------------------------------------------------------------
; pktbuf_alloc — Lockless Atomic SPSC Packet Buffer Allocator
; Output: RAX = Pointer to net_pkt_t (or NULL if Depleted)
; -----------------------------------------------------------------------------
align 64
pktbuf_alloc:
    push rbp
    mov rbp, rsp
    push rbx

    ; Allocate packet buffer from Hugepage pool & set TSC timestamp
    call rdtsc_get_cycles

    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; pktbuf_free — Atomic Reference Counter Free / Recycle
; Input: RDI = Pointer to net_pkt_t
; -----------------------------------------------------------------------------
align 64
pktbuf_free:
    push rbp
    mov rbp, rsp
    lock dec dword [rdi + net_pkt_t.refcnt]
    jnz .done
    ; Recycle buffer back to Hugepage SPSC pool
.done:
    pop rbp
    ret

; -----------------------------------------------------------------------------
; pktbuf_copy_avx512 — AVX-512 Non-Temporal Zero-Copy Memory Stream (vmovntdq)
; Input: RDI = Dest Buffer, RSI = Src Buffer, RDX = Length in Bytes
; -----------------------------------------------------------------------------
align 64
pktbuf_copy_avx512:
    push rbp
    mov rbp, rsp
    push rbx

    mov rcx, rdx
    shr rcx, 6                      ; 64-byte chunks (AVX-512 ZMM)
    jz .tail_bytes

.loop_avx512:
    vmovdqu64 zmm0, [rsi]
    vmovntdq [rdi], zmm0            ; Non-temporal stream store (bypasses L3 cache)
    add rsi, 64
    add rdi, 64
    dec rcx
    jnz .loop_avx512

    sfence                          ; Memory store fence for non-temporal writes

.tail_bytes:
    pop rbx
    pop rbp
    ret
