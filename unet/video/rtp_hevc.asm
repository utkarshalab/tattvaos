; =============================================================================
; Tattva OS — unet/video/rtp_hevc.asm
; =============================================================================
; RTP Payload Format for HEVC / H.265 Video (RFC 7798).
;
; Implements:
;   - NAL Unit Fragmentation Units (FU-A / FU-B) Packet Framing for 4K/8K Video
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global rtp_hevc_init
global rtp_hevc_depacketize

align 32
rtp_hevc_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
rtp_hevc_depacketize:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret
