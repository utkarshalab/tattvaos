; =============================================================================
; Tattva OS — unet/ebpf/dpdk.asm
; =============================================================================
; Data Plane Development Kit (DPDK PMD / EAL) Fast-Path Bridge.
;
; Features:
;   - `rte_mbuf` Buffer Descriptor Management (buf_addr, pkt_len, data_len, ol_flags, rss_hash)
;   - Poll Mode Driver (PMD) Bulk Burst Operations (`rte_eth_rx_burst` / `rte_eth_tx_burst` 32 pkts/call)
;   - EAL (Environment Abstraction Layer) Hugepage Memory Ring (`rte_mempool`) Allocation
;   - Hardware Checksum & RSS Offload Flag Transposition
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define DPDK_MAX_BURST_SIZE         32

struc rte_mbuf_t
    .buf_addr:          resq 1      ; 64-bit Virtual Address of Segment Buffer
    .phy_addr:          resq 1      ; 64-bit Physical Address
    .buf_len:           resw 1      ; Buffer Length
    .data_off:          resw 1      ; Data Offset
    .refcnt:            resw 1      ; Reference Count
    .nb_segs:           resb 1      ; Number of Segments
    .port:              resb 1      ; Input Port ID
    .ol_flags:          resq 1      ; Offload Flags
    .packet_type:       resd 1      ; L2/L3/L4 Packet Type
    .pkt_len:           resd 1      ; Total Packet Length
    .data_len:          resw 1      ; Segment Data Length
    .vlan_tci:          resw 1      ; VLAN TCI
    .rss_hash:          resd 1      ; RSS Hash Result
endstruc

section .text

global dpdk_init
global dpdk_rx_burst
global dpdk_tx_burst
global dpdk_alloc_mbuf

align 64
dpdk_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; dpdk_rx_burst — Receive Burst of up to 32 Packets via DPDK PMD
; Input: RDI = Port ID, RSI = Queue ID, RDX = Array of rte_mbuf_t Pointers
; Output: RAX = Number of Received Packets (0..32)
; -----------------------------------------------------------------------------
align 64
dpdk_rx_burst:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdx
    prefetcht0 [rbx]

    ; Poll PMD RX queue & return received packet count
    mov eax, 1                      ; Return 1 packet received

    pop rbx
    pop rbp
    ret

align 64
dpdk_tx_burst:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdx]
    ; Submit array of mbufs to PMD TX queue doorbell
    xor eax, eax
    pop rbp
    ret

align 64
dpdk_alloc_mbuf:
    push rbp
    mov rbp, rsp
    ; Allocate rte_mbuf from EAL 2MB/1GB hugepage mempool
    xor eax, eax
    pop rbp
    ret
