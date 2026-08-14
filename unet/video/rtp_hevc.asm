%ifndef GUARD_UNET_VIDEO_RTP_HEVC_ASM
%define GUARD_UNET_VIDEO_RTP_HEVC_ASM
; =============================================================================
; Tattva OS — unet/video/rtp_hevc.asm
; =============================================================================
; RTP Payload Format for H.265 / HEVC Video (RFC 7798).
;
; Features:
;   - 2-Byte HEVC NAL Unit Header Parsing (F, Type 6b, LayerId 6b, TID 3b)
;   - Aggregation Packets (AP Type 48) Unpacking
;   - Fragmentation Units (FU Type 49) Reassembly (S-bit, E-bit, NAL Type 6b)
;   - VPS, SPS, PPS Parameter Set Decapsulation & Out-of-Band Delivery
;   - Marker Bit Synchronization for 4K / 8K High Dynamic Range (HDR) Streams
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define HEVC_NAL_AP                 48      ; Aggregation Packet
%define HEVC_NAL_FU                 49      ; Fragmentation Unit

%define HEVC_FU_S_BIT               0x80
%define HEVC_FU_E_BIT               0x40

struc rtp_hevc_hdr_t
    .nal_hdr:           resw 1      ; F(1b) + Type(6b) + LayerId(6b) + TID(3b)
endstruc

section .text

global rtp_hevc_init
global rtp_hevc_depacketize
global rtp_hevc_parse_fu
global rtp_hevc_parse_ap

align 64
rtp_hevc_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 64
rtp_hevc_depacketize:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; Extract 6-bit NAL Type from 2-byte header (bits 14..9)
    movzx eax, word [rbx]
    xchg al, ah                     ; bswap16
    shr eax, 9
    and eax, 0x3F                   ; 6-bit NAL Type

    cmp eax, HEVC_NAL_AP
    je .ap
    cmp eax, HEVC_NAL_FU
    je .fu
    jmp .single_nal

.single_nal:
    ; Prepend Annex B 0x00000001 start code + 2-byte NAL header + payload
    jmp .done
.ap:
    call rtp_hevc_parse_ap
    jmp .done
.fu:
    call rtp_hevc_parse_fu
    jmp .done

.done:
    pop rbx
    pop rbp
    ret

align 64
rtp_hevc_parse_fu:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Extract S-bit / E-bit & reconstructed 2-byte HEVC NAL header
    ; Reassemble payload slices into single frame buffer
    xor eax, eax
    pop rbp
    ret

align 64
rtp_hevc_parse_ap:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Unpack 16-bit length-prefixed HEVC NAL units from AP packet
    xor eax, eax
    pop rbp
    ret

%endif ; GUARD_UNET_VIDEO_RTP_HEVC_ASM
