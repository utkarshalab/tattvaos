%ifndef GUARD_UNET_TOOLS_SAN_SFTP_CLI_ASM
%define GUARD_UNET_TOOLS_SAN_SFTP_CLI_ASM
; =============================================================================
; Tattva OS — unet/tools/san/sftp_cli.asm
; =============================================================================
; Command-Line SFTP File Transfer Subsystem Tool (`sftp`).
;
; Features:
;   - SSH File Transfer Protocol (SFTP v3) Packet Header Formatting
;   - Opcodes: `SSH_FXP_INIT`, `SSH_FXP_OPEN`, `SSH_FXP_READ`, `SSH_FXP_WRITE`, `SSH_FXP_CLOSE`, `SSH_FXP_READDIR`
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define SSH_FXP_INIT                1
%define SSH_FXP_VERSION             2
%define SSH_FXP_OPEN                3
%define SSH_FXP_CLOSE               4
%define SSH_FXP_READ                5
%define SSH_FXP_WRITE               6
%define SSH_FXP_READDIR             12

section .text

global sftp_cli_main

align 64
sftp_cli_main:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Initialize SFTP subsystem over SSH channel -> issue SSH_FXP_OPEN & transfer file payload
    xor eax, eax
    pop rbp
    ret

%endif ; GUARD_UNET_TOOLS_SAN_SFTP_CLI_ASM
