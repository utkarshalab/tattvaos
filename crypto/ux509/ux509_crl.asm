%ifndef GUARD_CRYPTO_UX509_UX509_CRL_ASM
%define GUARD_CRYPTO_UX509_UX509_CRL_ASM
; =============================================================================
; Tattva OS — crypto/ux509/ux509_crl.asm
; =============================================================================
; Certificate Revocation List (CRL) Serial Number Checker.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "crypto/ux509/ux509.inc"

section .text

; -----------------------------------------------------------------------------
; ux509_crl_check_revocation — Check if serial number is listed in CRL
; Input:  RDI = Certificate Serial Number Pointer (16 bytes)
;         RSI = CRL Binary Buffer Pointer
;         RDX = CRL Length in bytes
; Output: RAX = 1 (Clean / Not Revoked), 0 (REVOKED!)
; -----------------------------------------------------------------------------
ux509_crl_check_revocation:
    push rbx
    push rcx
    push rsi
    push rdi
    push r12
    push r13

    mov r12, rdi                    ; Target serial number
    mov r13, rsi                    ; CRL buffer pointer

    ; Iterate revoked serial numbers in CRL
    xor rbx, rbx
.crl_loop:
    cmp rbx, rdx
    jae .clean

    ; Compare 16-byte serial number
    mov rax, [r12 + 0]
    cmp rax, [r13 + rbx]
    jne .next_serial

    mov rax, [r12 + 8]
    cmp rax, [r13 + rbx + 8]
    je .revoked                     ; Match found -> REVOKED!

.next_serial:
    add rbx, 16
    jmp .crl_loop

.clean:
    mov rax, 1                      ; Clean / Not Revoked!
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rcx
    pop rbx
    ret

.revoked:
    xor rax, rax                    ; Revoked certificate!
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rcx
    pop rbx
    ret

%endif ; GUARD_CRYPTO_UX509_UX509_CRL_ASM
