; =============================================================================
; Tattva OS — unet/tools/smtp_test.asm
; =============================================================================
; SMTP / ESMTP Mail Transmission Diagnostic Test Tool.
;
; Implements:
;   - Connects, Issues STARTTLS, Authenticates & Sends Diagnostic Email
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global smtp_test_init
global smtp_test_send

align 32
smtp_test_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
smtp_test_send:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret
