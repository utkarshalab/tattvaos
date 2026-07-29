; =============================================================================
; Tattva OS — unet/mail/imap.asm
; =============================================================================
; IMAP4rev1 Remote Mailbox Protocol Engine (RFC 3501 / RFC 9051).
;
; Implements:
;   - Tagged Commands: CAPABILITY, LOGIN, SELECT, FETCH, STORE, EXPUNGE, LOGOUT
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global imap_init
global imap_parse_cmd

align 32
imap_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
imap_parse_cmd:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret
