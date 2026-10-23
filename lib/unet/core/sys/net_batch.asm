%ifndef GUARD_UNET_CORE_SYS_NET_BATCH_ASM
%define GUARD_UNET_CORE_SYS_NET_BATCH_ASM
; =============================================================================
; Utkarsha OS — unet/core/sys/net_batch.asm
; =============================================================================
; Batch RX/TX API for High-Performance Packet Processing
;
; Provides vectorized packet processing using:
;   - Batch enqueue/dequeue (DPDK-style)
;   - AVX-512/AVX2/SSE checksum offload
;   - Zero-copy packet cloning
;   - Multi-queue RSS/RFS support
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "lib/unet/unet.inc"

%define BATCH_MAX_PKTS          64        ; Max packets per batch
%define BATCH_PREFETCH_DIST     4         ; Prefetch distance

struc batch_t
    .pkts:              resq BATCH_MAX_PKTS  ; Packet pointers
    .count:             resd 1              ; Current packet count
    .flags:             resd 1              ; Batch flags
    .queue_id:          resd 1              ; RX/TX queue ID
    .timestamp:         resq 1              ; Batch timestamp
endstruc

%define BATCH_FLAG_RX             0x01
%define BATCH_FLAG_TX             0x02
%define BATCH_FLAG_CHECKSUM       0x04
%define BATCH_FLAG_ZERO_COPY      0x08
%define BATCH_FLAG_TSO            0x10

struc rx_batch_t
    .batch:             resb batch_t_size
    .rx_queue:          resq 1      ; Ring buffer pointer
    .prefetch_idx:      resd 1
    .stats_pkts:        resq 1
    .stats_bytes:       resq 1
    .stats_drops:       resq 1
    .stats_checksum_err: resq 1
endstruc

struc tx_batch_t
    .batch:             resb batch_t_size
    .tx_queue:          resq 1      ; Ring buffer pointer
    .tso_context:       resq 1      ; TSO segmentation context
    .stats_pkts:        resq 1
    .stats_bytes:       resq 1
    .stats_drops:       resq 1
endstruc

section .bss
alignb 64
global rx_batch_pool
rx_batch_pool:        resb rx_batch_t_size * 64  ; BATCH_POOL_SIZE batches

global tx_batch_pool
tx_batch_pool:        resb tx_batch_t_size * 64

; Field offsets inside the embedded batch_t (NASM strucs do not nest names)
%define RXB_PKTS        (rx_batch_t.batch + batch_t.pkts)
%define RXB_COUNT       (rx_batch_t.batch + batch_t.count)
%define RXB_FLAGS       (rx_batch_t.batch + batch_t.flags)
%define RXB_TIMESTAMP   (rx_batch_t.batch + batch_t.timestamp)
%define TXB_PKTS        (tx_batch_t.batch + batch_t.pkts)
%define TXB_COUNT       (tx_batch_t.batch + batch_t.count)
%define TXB_FLAGS       (tx_batch_t.batch + batch_t.flags)
%define TXB_TIMESTAMP   (tx_batch_t.batch + batch_t.timestamp)

%define BATCH_POOL_SIZE     64
%define PKT_FLAG_CSUM_BAD   0x01        ; net_pkt_t.flags: IPv4 checksum failed

section .text

global batch_rx_init
global batch_tx_init
global batch_rx_get
global batch_tx_get
global batch_rx_submit
global batch_tx_submit
global batch_rx_process_checksums
global batch_tx_build_checksums
global batch_pkt_clone
global batch_pkt_ref

; A pool slot is free while its batch flags are 0; batch_*_get claims a slot
; by setting BATCH_FLAG_RX / BATCH_FLAG_TX.

; =============================================================================
; batch_rx_init / batch_tx_init — Clear the batch pools
; =============================================================================
align 64
batch_rx_init:
    lea rdi, [rx_batch_pool]
    xor eax, eax
    mov ecx, (rx_batch_t_size * BATCH_POOL_SIZE)
    rep stosb
    ; TODO: per-CPU pools with proper CPU affinity
    xor eax, eax
    ret

align 64
batch_tx_init:
    lea rdi, [tx_batch_pool]
    xor eax, eax
    mov ecx, (tx_batch_t_size * BATCH_POOL_SIZE)
    rep stosb
    xor eax, eax
    ret

; =============================================================================
; batch_rx_get — Claim a free RX batch
; Output: RAX = rx_batch_t* or 0 if all are in use
; =============================================================================
align 64
batch_rx_get:
    push rbx
    lea rbx, [rx_batch_pool]
    mov ecx, BATCH_POOL_SIZE
.find_free:
    cmp dword [rbx + RXB_FLAGS], 0
    je .found
    add rbx, rx_batch_t_size
    dec ecx
    jnz .find_free
    xor eax, eax
    pop rbx
    ret
.found:
    mov dword [rbx + RXB_COUNT], 0
    mov dword [rbx + RXB_FLAGS], BATCH_FLAG_RX
    call rdtsc_get_cycles
    mov [rbx + RXB_TIMESTAMP], rax
    mov rax, rbx
    pop rbx
    ret

; =============================================================================
; batch_tx_get — Claim a free TX batch
; Output: RAX = tx_batch_t* or 0 if all are in use
; =============================================================================
align 64
batch_tx_get:
    push rbx
    lea rbx, [tx_batch_pool]
    mov ecx, BATCH_POOL_SIZE
.find_free:
    cmp dword [rbx + TXB_FLAGS], 0
    je .found
    add rbx, tx_batch_t_size
    dec ecx
    jnz .find_free
    xor eax, eax
    pop rbx
    ret
.found:
    mov dword [rbx + TXB_COUNT], 0
    mov dword [rbx + TXB_FLAGS], BATCH_FLAG_TX
    call rdtsc_get_cycles
    mov [rbx + TXB_TIMESTAMP], rax
    mov rax, rbx
    pop rbx
    ret

; =============================================================================
; batch_rx_submit / batch_tx_submit — Hand a batch to its ring
; Input: RDI = rx_batch_t* / tx_batch_t*
; Output: EAX = packets enqueued
;
; TODO: There is no ring-buffer API to enqueue into yet, so nothing is
; enqueued: these return 0 and leave the batch, its packets and the slot
; untouched for the caller to retry or release.
; =============================================================================
align 64
batch_rx_submit:
    xor eax, eax
    ret

align 64
batch_tx_submit:
    xor eax, eax
    ret

; =============================================================================
; batch_rx_process_checksums — Verify the IPv4 header checksum of every
; packet in an RX batch
; Input: RDI = rx_batch_t* (each packet's headroom_offset at its Ethernet
;        header)
; Output: EAX = number of packets that failed; each one also gets
;         PKT_FLAG_CSUM_BAD in net_pkt_t.flags and counts in stats_checksum_err
; =============================================================================
align 64
batch_rx_process_checksums:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi
    xor r14d, r14d              ; index
    xor r15d, r15d              ; failures

    call avx512_checksum_supported
    mov r13d, eax               ; 1: use the AVX-512 summing routine

.loop:
    cmp r14d, [rbx + RXB_COUNT]
    jae .done
    mov r12, [rbx + RXB_PKTS + r14 * 8]

    ; Only IPv4 frames carry a header checksum
    mov rdi, [r12 + net_pkt_t.virt_addr]
    mov eax, [r12 + net_pkt_t.headroom_offset]
    add rdi, rax
    cmp word [rdi + 12], 0x0008 ; EtherType 0x0800 (network order)
    jne .next
    add rdi, 14                 ; IPv4 header
    movzx esi, byte [rdi]
    and esi, 0x0F
    shl esi, 2                  ; IHL * 4

    test r13d, r13d
    jz .scalar
    call avx512_csum_partial
    jmp .check
.scalar:
    call ip_checksum_calc
.check:
    cmp ax, 0xFFFF
    je .next
    or byte [r12 + net_pkt_t.flags], PKT_FLAG_CSUM_BAD
    inc qword [rbx + rx_batch_t.stats_checksum_err]
    inc r15d

.next:
    inc r14d
    jmp .loop

.done:
    mov eax, r15d
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; =============================================================================
; batch_tx_build_checksums — Batch TX checksum building
; Input: RDI = tx_batch_t*
;
; Nothing to do yet: ip_output, tcp_* and udp_* fill in their checksums
; when each packet is built. TODO: move that here for batched transmit.
; =============================================================================
align 64
batch_tx_build_checksums:
    ret

; =============================================================================
; batch_pkt_clone — Zero-copy packet clone (shares the source's buffer)
; Input: RDI = src net_pkt_t*, RSI = dst net_pkt_t* (pre-allocated)
; Output: EAX = 0
;
; TODO: the reference count lives in each descriptor, not in the shared
; buffer, so the two descriptors do not yet agree on when it can be freed.
; =============================================================================
align 64
batch_pkt_clone:
    lock inc dword [rdi + net_pkt_t.ref_count]

    ; Copy metadata (not data)
    mov rax, [rdi + net_pkt_t.virt_addr]
    mov [rsi + net_pkt_t.virt_addr], rax
    mov rax, [rdi + net_pkt_t.phys_addr]
    mov [rsi + net_pkt_t.phys_addr], rax
    mov eax, [rdi + net_pkt_t.headroom_offset]
    mov [rsi + net_pkt_t.headroom_offset], eax
    mov eax, [rdi + net_pkt_t.data_len]
    mov [rsi + net_pkt_t.data_len], eax
    mov eax, [rdi + net_pkt_t.total_capacity]
    mov [rsi + net_pkt_t.total_capacity], eax
    mov eax, [rdi + net_pkt_t.ref_count]
    mov [rsi + net_pkt_t.ref_count], eax
    mov qword [rsi + net_pkt_t.next_pkt], 0
    mov qword [rsi + net_pkt_t.next], 0
    mov rax, [rdi + net_pkt_t.timestamp_ns]
    mov [rsi + net_pkt_t.timestamp_ns], rax
    mov al, [rdi + net_pkt_t.ttl]
    mov [rsi + net_pkt_t.ttl], al
    mov al, [rdi + net_pkt_t.flags]
    mov [rsi + net_pkt_t.flags], al
    mov al, [rdi + net_pkt_t.ecn]
    mov [rsi + net_pkt_t.ecn], al

    xor eax, eax
    ret

; =============================================================================
; batch_pkt_ref — Take another reference on a packet
; Input: RDI = net_pkt_t*
; =============================================================================
align 32
batch_pkt_ref:
    lock inc dword [rdi + net_pkt_t.ref_count]
    ret

%endif ; GUARD_UNET_CORE_SYS_NET_BATCH_ASM
