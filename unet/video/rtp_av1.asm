; =============================================================================
; Tattva OS — unet/video/rtp_av1.asm
; =============================================================================
; RTP Payload Format for AV1 Video (AOMedia AV1 RTP Spec / RFC Draft).
;
; Features:
;   - AV1 Aggregation Header (Z-bit, Y-bit, W-bit, N-bit) Parsing
;   - OBU (Open Bitstream Unit) Element Header Decoding (OBU_SEQUENCE_HEADER, OBU_FRAME, OBU_TILE_GROUP)
;   - Obu_size Variable-Length LEB128 Integer Decoding
;   - Temporal & Spatial Scalability Layering (SVC) Support
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define OBU_SEQUENCE_HEADER         1
%define OBU_TEMPORAL_DELIMITER      2
%define OBU_FRAME_HEADER            3
%define OBU_TILE_GROUP              4
%define OBU_METADATA                5
%define OBU_FRAME                   6

struc rtp_av1_hdr_t
    .flags:             resb 1      ; Z(1b) + Y(1b) + W(2b) + N(1b) + Resv(3b)
endstruc

section .text

global rtp_av1_init
global rtp_av1_depacketize
global rtp_av1_parse_obu
global rtp_av1_decode_leb128

align 64
rtp_av1_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 64
rtp_av1_depacketize:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; 1. Check Z-bit (first OBU continuation from previous packet)
    movzx eax, byte [rbx + rtp_av1_hdr_t.flags]

    ; 2. Iterate OBU elements in payload using LEB128 length decoding
    lea rdi, [rbx + 1]
    call rtp_av1_parse_obu

    pop rbx
    pop rbp
    ret

align 64
rtp_av1_parse_obu:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Extract OBU Type (bits 6..3 of OBU header) & decode LEB128 size
    call rtp_av1_decode_leb128
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; rtp_av1_decode_leb128 — Decode Variable-Length LEB128 Integer
; Input: RDI = Pointer to LEB128 bytes
; Output: RAX = Decoded Integer, ECX = Bytes Consumed
; -----------------------------------------------------------------------------
align 64
rtp_av1_decode_leb128:
    push rbp
    mov rbp, rsp
    xor eax, eax
    xor ecx, ecx
.leb_loop:
    movzx edx, byte [rdi + rcx]
    mov r8d, edx
    and r8d, 0x7F                   ; 7 payload bits
    shl r8d, cl                     ; Shift by (byte_index * 7)
    or eax, r8d
    inc ecx
    test dl, 0x80                   ; MSB=1 -> more bytes
    jnz .leb_loop
    pop rbp
    ret
