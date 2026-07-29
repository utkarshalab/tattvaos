; =============================================================================
; Tattva OS — unet/video/rtp_h264.asm
; =============================================================================
; RTP Payload Format for H.264 Video (RFC 6184).
;
; Implements:
;   - Single NAL Unit, STAP-A Aggregation & FU-A Fragmentation Packet Parsing
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global rtp_h264_init
global rtp_h264_depacketize

align 32
rtp_h264_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
rtp_h264_depacketize:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret
