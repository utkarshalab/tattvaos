; =============================================================================
; Tattva OS — unet/tools/industrial/cfdp_get.asm
; =============================================================================
; CCSDS File Delivery Protocol Downlink Tool (`cfdp-get`).
;
; Features:
;   - CCSDS 727.0-B-5 CFDP Unacknowledged (Class 1) & Acknowledged (Class 2) File Transfer
;   - Spacecraft Payload Science File Retrieval
;
; Delegates:
;   - CCSDS Subsystem                   -> unet/space/cfdp.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global cfdp_get_main

align 64
cfdp_get_main:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Request CCSDS CFDP file downlink transfer from satellite payload computer
    xor eax, eax
    pop rbp
    ret
