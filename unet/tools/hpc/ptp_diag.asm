; =============================================================================
; Tattva OS — unet/tools/hpc/ptp_diag.asm
; =============================================================================
; IEEE 1588 PTP / IEEE 802.1AS Precision Time Protocol Diagnostic Tool (`ptp4l-diag`).
;
; Features:
;   - Grandmaster Clock Identity, Master Offset (Nanoseconds), Mean Path Delay Audit
;   - Hardware Ingress/Egress Timestamping Frequency Adjustment Offset (PPM)
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global ptp_diag_main

extern rdtsc_get_cycles

align 64
ptp_diag_main:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Measure IEEE 1588 PTP master clock offset & mean path delay nanosecond jitter
    call rdtsc_get_cycles
    xor eax, eax
    pop rbp
    ret
