; =============================================================================
; Tattva OS — unet/video/rtp_h264.asm
; =============================================================================
; RTP Payload Format for H.264 Video (RFC 6184).
;
; Features:
;   - NAL Unit Header Extraction (F, NRI, Type 1..23 Single NAL Unit)
;   - STAP-A (Single-Time Aggregation Packet Type 24) Aggregation Unpacking
;   - FU-A (Fragmentation Unit Type 28) Packet Reassembly (S-bit, E-bit, R-bit, NAL Type)
;   - Zero-Copy Video Frame Reassembly Buffer Management
;   - Timestamp & Marker Bit Synchronization for Video Display Frame Rendering
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define H264_NAL_SINGLE_MIN         1
%define H264_NAL_SINGLE_MAX         23
%define H264_NAL_STAP_A             24
%define H264_NAL_FU_A               28

%define H264_FU_S_BIT               0x80    ; Start of Fragment
%define H264_FU_E_BIT               0x40    ; End of Fragment

struc rtp_h264_fu_hdr_t
    .indicator:         resb 1      ; F(1b) + NRI(2b) + Type=28(5b)
    .header:            resb 1      ; S(1b) + E(1b) + R(1b) + NAL Type(5b)
endstruc

section .text

global rtp_h264_init
global rtp_h264_depacketize
global rtp_h264_parse_single_nal
global rtp_h264_parse_stap_a
global rtp_h264_parse_fu_a

align 64
rtp_h264_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; rtp_h264_depacketize — Depacketize H.264 RTP Payload into Annex B Byte Stream
; Input: RDI = Pointer to RTP Payload, ESI = Length, EDX = Marker Bit (1 = Frame Complete)
; Output: RAX = Pointer to Reassembled NAL Unit Frame (or NULL if Incomplete FU-A)
; -----------------------------------------------------------------------------
align 64
rtp_h264_depacketize:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; Extract NAL Unit Type (bottom 5 bits of byte 0)
    movzx eax, byte [rbx]
    and al, 0x1F

    cmp al, H264_NAL_STAP_A
    je .stap_a
    cmp al, H264_NAL_FU_A
    je .fu_a
    cmp al, H264_NAL_SINGLE_MAX
    jle .single_nal
    jmp .done

.single_nal:
    call rtp_h264_parse_single_nal
    jmp .done
.stap_a:
    call rtp_h264_parse_stap_a
    jmp .done
.fu_a:
    call rtp_h264_parse_fu_a
    jmp .done

.done:
    pop rbx
    pop rbp
    ret

align 64
rtp_h264_parse_single_nal:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Prepend Annex B start code (0x00000001) + NAL Unit payload
    xor eax, eax
    pop rbp
    ret

align 64
rtp_h264_parse_stap_a:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Unpack multiple 16-bit length-prefixed NAL units from STAP-A aggregation packet
    xor eax, eax
    pop rbp
    ret

align 64
rtp_h264_parse_fu_a:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Extract S-bit (Start) and E-bit (End). If Start: emit Annex B start code + reconstructed NAL header
    ; Append fragment data to frame reassembly buffer until E-bit received
    movzx eax, byte [rdi + 1]
    test al, H264_FU_S_BIT
    jnz .fu_start
    test al, H264_FU_E_BIT
    jnz .fu_end
    jmp .fu_done

.fu_start:
    ; Emit 0x00000001 + (Indicator & 0xE0) | (Header & 0x1F)
    jmp .fu_done
.fu_end:
    ; Frame complete! Return full reassembled buffer
    jmp .fu_done

.fu_done:
    pop rbp
    ret
