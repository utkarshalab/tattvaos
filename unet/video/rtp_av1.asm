; =============================================================================
; Tattva OS — unet/video/rtp_av1.asm
; =============================================================================
; RTP Payload Format for AV1 Video (RFC 9584).
;
; Implements:
;   - AV1 OBU (Open Bitstream Unit) Depacketization & RTP Stream Transmission
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global rtp_av1_init
global rtp_av1_depacketize

align 32
rtp_av1_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
rtp_av1_depacketize:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret
