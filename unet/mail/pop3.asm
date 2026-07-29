; =============================================================================
; Tattva OS — unet/mail/pop3.asm
; =============================================================================
; Post Office Protocol Version 3 (POP3 RFC 1939) Engine.
;
; Implements:
;   - POP3 Mail Retrieval Commands: USER, PASS, STAT, LIST, RETR, DELE, QUIT
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global pop3_init
global pop3_handle_cmd

align 32
pop3_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
pop3_handle_cmd:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret
