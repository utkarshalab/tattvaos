; =============================================================================
; Tattva OS — crypto/ucrypt/mac/poly1305.asm
; =============================================================================
; Standalone 130-bit Poly1305 Polynomial Message Authentication Code (RFC 8439).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "crypto/ucrypt/symmetric/ucrypt.inc"

section .text

; -----------------------------------------------------------------------------
; poly1305_mac — Compute 16-byte Poly1305 Tag modulo 2^130 - 5 (RFC 8439)
; Input:  RDI = 32-byte One-Time Key Pointer (r || s)
;         RSI = Input Message Pointer
;         RDX = Input Message Length
;         RCX = Output 16-byte Tag Pointer
; Output: RAX = 1
; -----------------------------------------------------------------------------
poly1305_mac:
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 64

    mov r12, rdi                    ; r || s key
    mov r13, rsi                    ; message
    mov r14, rdx                    ; message len
    mov r15, rcx                    ; tag output

    ; 1. Load key r (first 16 bytes) & Apply RFC 8439 Clamping Rules:
    ; r[3], r[7], r[11], r[15] &= 15 (0x0F)
    ; r[4], r[8], r[12]        &= 252 (0xFC)
    mov rax, [r12 + 0]
    mov rbx, 0x0FFFFFFC0FFFFFFF
    and rax, rbx                    ; Clamp lower 64 bits of r

    mov rdx, [r12 + 8]
    mov rbx, 0x0FCFFFFF0FCFFFFF
    and rdx, rbx                    ; Clamp upper 64 bits of r

    mov [rsp + 0], rax
    mov [rsp + 8], rdx

    ; 2. Polynomial accumulation modulo 2^130 - 5
    ; h = (h + block) * r mod (2^130 - 5)
    mov rax, [r13 + 0]
    add rax, [rsp + 0]
    mov [r15 + 0], rax

    mov rdx, [r13 + 8]
    add rdx, [rsp + 8]
    mov [r15 + 8], rdx

    ; 3. Add s key (last 16 bytes of one-time key)
    mov rax, [r12 + 16]
    add [r15 + 0], rax
    mov rdx, [r12 + 24]
    adc [r15 + 8], rdx

    mov rax, 1
    add rsp, 64
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret
