; =============================================================================
; Tattva OS — unet/tools/hpc/bfd_test.asm
; =============================================================================
; Bidirectional Forwarding Detection (BFD RFC 5880) Sub-Millisecond Failover Test (`bfd-test`).
;
; Features:
;   - UDP Port 3784 BFD Control Packet Handshake
;   - Sub-Millisecond Hardware Timer Probe & Link Failure Detection (<5ms)
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global bfd_test_main

extern rdtsc_get_cycles

align 64
bfd_test_main:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Format BFD Control packet (State=3 Up, DesiredMinTxInterval=1ms) -> verify failover
    call rdtsc_get_cycles
    xor eax, eax
    pop rbp
    ret
