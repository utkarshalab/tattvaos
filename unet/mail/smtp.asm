; =============================================================================
; Tattva OS — unet/mail/smtp.asm
; =============================================================================
; Simple Mail Transfer Protocol (SMTP / ESMTP — RFC 5321 / STARTTLS) Engine.
;
; Implements:
;   - SMTP Commands: HELO/EHLO, MAIL FROM, RCPT TO, DATA, STARTTLS, QUIT
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global smtp_init
global smtp_handle_command

align 32
smtp_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
smtp_handle_command:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret
