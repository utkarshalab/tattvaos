; =============================================================================
; Tattva OS — unet/tools/hpc/slingshot_stat.asm
; =============================================================================
; Cray Slingshot Interconnect Telemetry Statistics Tool (`slingshot-stat`).
;
; Features:
;   - Slingshot Advanced Congestion Control (SACC) Frame Count, Drops, Retransmits
;   - Per-Virtual-Channel Throughput & Latency Distribution
;
; Delegates:
;   - Slingshot Engine                  -> unet/hpc/slingshot.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global slingshot_stat_main

extern slingshot_process_frame

align 64
slingshot_stat_main:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Collect SACC congestion notification frame counts & VC credit stats
    call slingshot_process_frame
    pop rbp
    ret
