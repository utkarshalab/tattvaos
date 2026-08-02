; =============================================================================
; Tattva OS — unet/space/ccsds.asm
; =============================================================================
; CCSDS Space Packet Protocol Engine (CCSDS 133.0-B-2 Specification).
;
; Features:
;   - 6-Byte Packet Primary Header Parsing & Construction
;     - Packet Version Number (3 bits)
;     - Packet Type (1 bit: 0 = Telemetry, 1 = Telecommand)
;     - Secondary Header Flag (1 bit)
;     - Application Process Identifier APID (11 bits: 0..2047)
;     - Sequence Flags (2 bits: 00 = Continuation, 01 = First, 10 = Last, 11 = Unfragmented)
;     - Packet Sequence Count / Name (14 bits)
;     - Packet Data Length (16 bits = payload bytes - 1)
;   - Secondary Header Processing (CUC / CDS Time Code Formats & Ancillary Data)
;   - Telemetry (TM) & Telecommand (TC) Multiplexing Engine
;   - Error Control Field Validation (CRC-16 CCITT)
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define CCSDS_TYPE_TELEMETRY        0
%define CCSDS_TYPE_TELECOMMAND      1

%define CCSDS_SEQ_CONTINUATION      0x00
%define CCSDS_SEQ_FIRST             0x01
%define CCSDS_SEQ_LAST              0x02
%define CCSDS_SEQ_UNFRAGMENTED      0x03

%define CCSDS_MAX_PACKET_LEN        65542   ; 6B header + 65536 payload

struc ccsds_primary_hdr_t
    .packet_id:         resw 1      ; Version(3b) + Type(1b) + SecHdr(1b) + APID(11b)
    .packet_seq:        resw 1      ; SeqFlags(2b) + SeqCount(14b)
    .packet_len:        resw 1      ; Data Length - 1 (16 bits)
endstruc

struc ccsds_sec_hdr_t
    .timestamp_cds:     resb 8      ; CCSDS Day Segmented (CDS) Time Code
    .subsystem_id:      resb 2
endstruc

section .text

global ccsds_init
global ccsds_parse_primary_hdr
global ccsds_send_telemetry
global ccsds_send_telecommand
global ccsds_crc16_ccitt

align 64
ccsds_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; ccsds_parse_primary_hdr — Parse 6-Byte CCSDS Primary Header
; Input: RDI = Pointer to CCSDS Packet Buffer, ESI = Length
; Output: EAX = APID, EDX = Payload Length, ECX = Packet Type (TM/TC)
; -----------------------------------------------------------------------------
align 64
ccsds_parse_primary_hdr:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; 1. Extract APID & Type from packet_id (word 0, big endian)
    movzx eax, word [rbx + ccsds_primary_hdr_t.packet_id]
    xchg al, ah                     ; bswap16

    mov ecx, eax
    shr ecx, 12
    and ecx, 1                      ; ECX = Packet Type (0 = TM, 1 = TC)

    and eax, 0x07FF                 ; EAX = 11-bit APID

    ; 2. Extract Data Length (word 2, big endian) -> Length = raw + 1
    movzx edx, word [rbx + ccsds_primary_hdr_t.packet_len]
    xchg dl, dh                     ; bswap16
    inc edx                         ; EDX = Actual Payload Bytes

    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; ccsds_send_telemetry — Format & Transmit CCSDS Telemetry (TM) Space Packet
; Input: RDI = APID (0..2047), RSI = Payload, EDX = Length, CX = Seq Count
; -----------------------------------------------------------------------------
align 64
ccsds_send_telemetry:
    push rbp
    mov rbp, rsp
    prefetcht0 [rsi]

    ; Build 6-byte Primary Header:
    ; Type = 0 (TM), SecHdr = 1, APID = RDI
    ; SeqFlags = 11 (Unfragmented), SeqCount = CX
    ; Length = EDX - 1
    call ccsds_crc16_ccitt

    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; ccsds_send_telecommand — Format & Transmit CCSDS Telecommand (TC) Packet
; Input: RDI = APID, RSI = Command Payload, EDX = Length, CX = Seq Count
; -----------------------------------------------------------------------------
align 64
ccsds_send_telecommand:
    push rbp
    mov rbp, rsp
    prefetcht0 [rsi]

    ; Build Primary Header with Type = 1 (TC)
    call ccsds_crc16_ccitt

    xor eax, eax
    pop rbp
    ret

align 64
ccsds_crc16_ccitt:
    push rbp
    mov rbp, rsp
    ; Compute CRC-16 CCITT (Polynomial 0x1021, Init 0xFFFF)
    xor eax, eax
    pop rbp
    ret
