%ifndef GUARD_UNET_CORE_SYS_PKTBUF_ASM
%define GUARD_UNET_CORE_SYS_PKTBUF_ASM
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
%include "lib/mem/mem.inc"

%define PKTBUF_SIZE                 2048
%define PKTBUF_HEADROOM             128

; net_pktbuf_t (head/data/tail/end skb-style view) is kept for anything that
; still wants to walk a buffer that way, but nothing under unet/core/ actually
; passes descriptors around in this shape: eth_input, arp_input, ip_input and
; every L4 handler take `net_pkt_t*` (unet.inc) instead, indexing off
; .virt_addr/.headroom_offset/.data_len. pktbuf_alloc below allocates and
; returns that type so its output is actually consumable by the rest of the
; stack; a net_pktbuf_t-shaped cache was never wired to anything that reads
; one, so it stayed unused.
struc net_pktbuf_t
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

section .bss
alignb 8
; Two slab caches: one for the fixed-size net_pkt_t descriptor, one for the
; 2048-byte data buffer it points at. Kept separate so a descriptor can be
; recycled (e.g. re-queued on a retransmit list) without recopying payload.
pktbuf_desc_cache:  resb kmem_cache_t_size
pktbuf_data_cache:  resb kmem_cache_t_size

section .data
pktbuf_desc_cache_name: db "net_pkt_desc", 0
pktbuf_data_cache_name: db "net_pkt_data", 0

section .text

global pktbuf_init
global pktbuf_alloc
global pktbuf_free
global pktbuf_copy_avx512


; -----------------------------------------------------------------------------
; pktbuf_init — Create the descriptor and data-buffer slab caches.
;
; lib/mem/dma.asm has no real hugepage allocator behind it yet (dma_alloc_
; hugepage is a fail-closed stub in kernel/unimplemented.asm), so packet
; buffers come from the real, already-working kmem_cache/heap allocator
; instead of a DMA hugepage pool that doesn't exist. Once lib/mem grows a
; real hugepage path this can switch over without touching any caller —
; pktbuf_alloc/free are the only things that know where a buffer comes from.
; -----------------------------------------------------------------------------
align 64
pktbuf_init:
    push rbp
    mov rbp, rsp

    lea rdi, [pktbuf_desc_cache]
    lea rsi, [pktbuf_desc_cache_name]
    mov rdx, net_pkt_t_size
    mov rcx, 64
    xor r8, r8
    xor r9, r9
    call kmem_cache_create_in_place

    lea rdi, [pktbuf_data_cache]
    lea rsi, [pktbuf_data_cache_name]
    mov rdx, PKTBUF_SIZE
    mov rcx, 64
    xor r8, r8
    xor r9, r9
    call kmem_cache_create_in_place

    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; pktbuf_alloc — Allocate a net_pkt_t descriptor plus its 2048-byte backing
; buffer, ready for a header to be filled in at PKTBUF_HEADROOM bytes in.
; Output: RAX = Pointer to net_pkt_t (or NULL if Depleted)
; -----------------------------------------------------------------------------
align 64
pktbuf_alloc:
    push rbp
    mov rbp, rsp
    push rbx

    lea rdi, [pktbuf_desc_cache]
    call kmem_cache_alloc
    test rax, rax
    jz .done                        ; OOM: no descriptor available
    mov rbx, rax                    ; RBX = net_pkt_t*

    lea rdi, [pktbuf_data_cache]
    call kmem_cache_alloc
    test rax, rax
    jnz .have_data

    ; Data buffer OOM: hand the descriptor back rather than leak it.
    lea rdi, [pktbuf_desc_cache]
    mov rsi, rbx
    call kmem_cache_free
    xor eax, eax
    jmp .done

.have_data:
    ; No virt_to_phys translation exists yet (lib/mem never grew one) — the
    ; kernel heap this cache is backed by runs identity-mapped today (see
    ; lib/mem/virt/pf.asm's PTE handling), so virt == phys holds for now.
    ; This is the one place that assumption would need to change.
    mov [rbx + net_pkt_t.virt_addr], rax
    mov [rbx + net_pkt_t.phys_addr], rax
    mov dword [rbx + net_pkt_t.headroom_offset], PKTBUF_HEADROOM
    mov dword [rbx + net_pkt_t.data_len], 0
    mov dword [rbx + net_pkt_t.total_capacity], PKTBUF_SIZE
    mov dword [rbx + net_pkt_t.ref_count], 1
    mov qword [rbx + net_pkt_t.next_pkt], 0
    mov qword [rbx + net_pkt_t.next], 0
    mov byte [rbx + net_pkt_t.ttl], 0
    mov byte [rbx + net_pkt_t.flags], 0

    call rdtsc_get_cycles
    mov [rbx + net_pkt_t.timestamp_ns], rax

    mov rax, rbx

.done:
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
    push rbx

    test rdi, rdi
    jz .done
    mov rbx, rdi

    lock dec dword [rbx + net_pkt_t.ref_count]
    jnz .done

    mov rdi, [rbx + net_pkt_t.virt_addr]
    test rdi, rdi
    jz .free_desc
    push rbx
    lea rdi, [pktbuf_data_cache]
    mov rsi, [rbx + net_pkt_t.virt_addr]
    call kmem_cache_free
    pop rbx

.free_desc:
    lea rdi, [pktbuf_desc_cache]
    mov rsi, rbx
    call kmem_cache_free

.done:
    pop rbx
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

%endif ; GUARD_UNET_CORE_SYS_PKTBUF_ASM
