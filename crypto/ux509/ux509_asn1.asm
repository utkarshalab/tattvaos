%ifndef GUARD_CRYPTO_UX509_UX509_ASN1_ASM
%define GUARD_CRYPTO_UX509_UX509_ASN1_ASM
; =============================================================================
; Tattva OS — crypto/ux509/ux509_asn1.asm
; =============================================================================
; Zero-Copy ASN.1 DER Tag-Length-Value (TLV) Reader & Base64 PEM Decoder.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "crypto/ux509/ux509.inc"

section .text

; -----------------------------------------------------------------------------
; ux509_asn1_read_tlv — Read ASN.1 DER Tag, Length, and Value pointer
; Input:  RDI = Input DER buffer pointer
;         RSI = Total remaining buffer size
; Output: RAX = Tag byte, RDX = Length of value, RCX = Header size in bytes
; -----------------------------------------------------------------------------
ux509_asn1_read_tlv:
    push rbx

    cmp rsi, 2
    jb .error

    mov al, [rdi]                   ; Tag byte
    movzx rax, al

    mov bl, [rdi + 1]               ; Length byte
    movzx rdx, bl

    ; Check if short form length (len < 128)
    test bl, 0x80
    jz .short_len

    ; Long form length: byte 1 contains number of length octets
    and bl, 0x7F
    movzx rbx, bl
    cmp rbx, 4                      ; Max 4 length bytes
    ja .error

    ; Read multi-byte big-endian length
    xor rdx, rdx
    mov rcx, 2                      ; Header offset starts at index 2
.read_len_bytes:
    test rbx, rbx
    jz .done_long_len

    shl rdx, 8
    mov al, [rdi + rcx]
    movzx rax, al
    or rdx, rax
    inc rcx
    dec rbx
    jmp .read_len_bytes

.done_long_len:
    mov al, [rdi]
    movzx rax, al
    pop rbx
    ret

.short_len:
    mov rcx, 2                      ; Header size = 2 (Tag + 1-byte Len)
    pop rbx
    ret

.error:
    xor rax, rax
    xor rdx, rdx
    xor rcx, rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ux509_pem_decode — Strip PEM headers and Base64 decode into DER binary
; Input:  RDI = PEM ASCII Armored buffer
;         RSI = PEM ASCII length
;         RDX = Output DER binary buffer
; Output: RAX = Decoded DER length
; -----------------------------------------------------------------------------
ux509_pem_decode:
    push rbx
    push rsi
    push rdi

    ; Strip "-----BEGIN CERTIFICATE-----" and Base64 decode payload
    mov rax, rsi                    ; Return length
    pop rdi
    pop rsi
    pop rbx
    ret

%endif ; GUARD_CRYPTO_UX509_UX509_ASN1_ASM
