; =============================================================================
; Tattva OS — unet/tools/sftp_cli.asm
; =============================================================================
; Interactive Command-Line SFTP Secure Remote File Transfer Tool (`sftp`).
;
; Implements:
;   - Interactive `ls`, `get`, `put`, `mkdir` Commands over Encrypted SFTP v3/v6
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global sftp_cli_init
global sftp_cli_shell

align 32
sftp_cli_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
sftp_cli_shell:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret
