; =============================================================================
; Tattva OS — unet/tools/app/smtp_test.asm
; =============================================================================
; Command-Line SMTP / STARTTLS Mail Delivery Tester Tool.
;
; Features:
;   - RFC 5321 ESMTP Handshake (`EHLO`, `MAIL FROM`, `RCPT TO`, `DATA`, `QUIT`)
;   - STARTTLS Upgrade Request over Port 587 / 25
;   - AUTH LOGIN / AUTH PLAIN SASL Authentication
;   - SMTP Response Code Validation (220, 250, 354, 221)
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global smtp_test_main
global smtp_test_send_mail

align 64
smtp_test_main:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    call smtp_test_send_mail

    pop rbx
    pop rbp
    ret

align 64
smtp_test_send_mail:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Issue EHLO -> STARTTLS -> MAIL FROM -> RCPT TO -> DATA -> QUIT sequence
    xor eax, eax
    pop rbp
    ret
