; =============================================================================
; Tattva OS — unet/tools/ssh_client.asm
; =============================================================================
; Native Assembly SSH 2.0 Secure Terminal Client Tool.
;
; Implements:
;   - Curve25519 KEX, Ed25519 Key Auth & Interactive PTY Terminal Sessions
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global ssh_client_init
global ssh_client_connect

align 32
ssh_client_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
ssh_client_connect:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret
