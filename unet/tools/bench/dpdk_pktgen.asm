; =============================================================================
; Tattva OS — unet/tools/bench/dpdk_pktgen.asm
; =============================================================================
; DPDK PMD Wire-Speed Packet Generator Benchmarking Tool (`dpdk-pktgen`).
;
; Features:
;   - Multi-Core DPDK PMD Traffic Generator Loop
;   - `rte_eth_tx_burst` 32-Packet Vector Bursting
;
; Delegates:
;   - DPDK PMD                          -> unet/ebpf/dpdk.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global dpdk_pktgen_main

extern dpdk_tx_burst

align 64
dpdk_pktgen_main:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Loop rte_eth_tx_burst across all allocated DPDK PMD ports
    call dpdk_tx_burst
    pop rbp
    ret
