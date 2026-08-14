%ifndef GUARD_UNET_TOOLS_INDUSTRIAL_AFDX_MON_ASM
%define GUARD_UNET_TOOLS_INDUSTRIAL_AFDX_MON_ASM
; =============================================================================
; Tattva OS — unet/tools/industrial/afdx_mon.asm
; =============================================================================
; ARINC 664 AFDX Avionics Network Traffic Monitor Tool (`afdx-mon`).
;
; Features:
;   - Real-Time Virtual Link (VL ID) Bandwidth, BAG Jitter, and Sequence Error Audit
;   - Redundancy Channel A vs Channel B Skew Time Measurement
;
; Delegates:
;   - AFDX Engine                       -> unet/avionics/afdx.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global afdx_mon_main


align 64
afdx_mon_main:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Monitor AFDX Virtual Link (VL ID) sequence numbers & dual channel skew times
    call afdx_process_frame
    pop rbp
    ret

%endif ; GUARD_UNET_TOOLS_INDUSTRIAL_AFDX_MON_ASM
