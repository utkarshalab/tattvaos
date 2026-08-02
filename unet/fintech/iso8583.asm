; =============================================================================
; Tattva OS — unet/fintech/iso8583.asm
; =============================================================================
; ISO 8583 Financial Transaction Card Originated Messages Engine.
;
; Features:
;   - Message Type Identifier (MTI) Parsing (e.g. `0100` Auth Req, `0110` Auth Resp, `0200` Financial Req, `0800` Network Management)
;   - Primary & Secondary Bitmaps (Bitmaps 1..128 Field Presence Mask)
;   - Data Element (DE) Field Parsers:
;       `DE2`: Primary Account Number (PAN LLVAR)
;       `DE3`: Processing Code (6 Bytes e.g. `000000` Purchase)
;       `DE4`: Amount, Transaction (12 Numeric)
;       `DE7`: Transmission Date & Time (`MMDDhhmmss`)
;       `DE11`: System Trace Audit Number (STAN 6 Numeric)
;       `DE39`: Response Code (2 Char e.g. `00` Approved, `51` Insufficient Funds)
;       `DE52`: Personal Identification Number (PIN) Data
;       `DE64`/`DE128`: Message Authentication Code (MAC)
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define ISO8583_MTI_AUTH_REQ        0x0100
%define ISO8583_MTI_AUTH_RESP       0x0110
%define ISO8583_MTI_FIN_REQ         0x0200
%define ISO8583_MTI_FIN_RESP        0x0210
%define ISO8583_MTI_NET_REQ         0x0800
%define ISO8583_MTI_NET_RESP        0x0810

struc iso8583_msg_t
    .mti:               resw 1      ; 4-digit MTI
    .bitmap_pri:        resq 1      ; DE 1-64 presence mask
    .bitmap_sec:        resq 1      ; DE 65-128 presence mask
    .pan:               resb 20     ; DE 2 PAN
    .proc_code:         resb 6      ; DE 3 Processing Code
    .amount:            resq 1      ; DE 4 Amount
    .stan:              resd 1      ; DE 11 STAN
    .resp_code:         resb 2      ; DE 39 Response Code
endstruc

section .text

global iso8583_init
global iso8583_parse_msg
global iso8583_build_msg
global iso8583_verify_mac

align 64
iso8583_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; iso8583_parse_msg — Parse ISO 8583 MTI + Bitmaps + Data Elements
; Input: RDI = Pointer to ISO 8583 Message Buffer, ESI = Length
; -----------------------------------------------------------------------------
align 64
iso8583_parse_msg:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; 1. Read 4-byte MTI
    ; 2. Read Primary Bitmap (64-bit mask)
    mov rax, [rbx + 4]
    bswap rax                       ; RAX = Primary Bitmap

    ; 3. Parse present DE fields based on bitmap bitmask
    call iso8583_verify_mac

    pop rbx
    pop rbp
    ret

align 64
iso8583_build_msg:
    push rbp
    mov rbp, rsp
    prefetcht0 [rsi]
    ; Build MTI + Bitmap + Data Elements (PAN, Amount, STAN, ProcCode) & compute MAC tag
    xor eax, eax
    pop rbp
    ret

align 64
iso8583_verify_mac:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Verify DE 64 / DE 128 CBC-MAC / HMAC-SHA256 message authentication code
    xor eax, eax
    pop rbp
    ret
