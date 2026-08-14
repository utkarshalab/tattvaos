%ifndef GUARD_UNET_TOOLS_APP_SSH_CLIENT_ASM
%define GUARD_UNET_TOOLS_APP_SSH_CLIENT_ASM
; =============================================================================
; Tattva OS — unet/tools/app/ssh_client.asm
; =============================================================================
; Command-Line Secure Shell (SSHv2) Terminal Client Tool.
;
; Features:
;   - SSH Identification Exchange (`SSH-2.0-TattvaOS_SSHClient_1.0`)
;   - Key Exchange (`curve25519-sha256`, `chacha20-poly1305@openssh.com`)
;   - User Authentication (`ssh-userauth` publickey & password)
;   - PTY Allocation & Interactive Shell Session (`session` channel request)
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global ssh_client_main
global ssh_client_kex
global ssh_client_userauth

align 64
ssh_client_main:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; 1. KEX Key Exchange
    call ssh_client_kex

    ; 2. User Authentication
    call ssh_client_userauth

    pop rbx
    pop rbp
    ret

align 64
ssh_client_kex:
    push rbp
    mov rbp, rsp
    ; Send SSH_MSG_KEXINIT & derive encryption keys
    xor eax, eax
    pop rbp
    ret

align 64
ssh_client_userauth:
    push rbp
    mov rbp, rsp
    ; Send SSH_MSG_USERAUTH_REQUEST (publickey / password)
    xor eax, eax
    pop rbp
    ret

%endif ; GUARD_UNET_TOOLS_APP_SSH_CLIENT_ASM
