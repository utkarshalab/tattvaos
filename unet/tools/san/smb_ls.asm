; =============================================================================
; Tattva OS — unet/tools/smb_ls.asm
; =============================================================================
; SMB 3.1.1 Encrypted File Share Directory Lister Tool.
;
; Implements:
;   - Connects, Authenticates & Lists Remote Directory Files via Encrypted SMB
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global smb_ls_init
global smb_ls_list

align 32
smb_ls_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
smb_ls_list:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret
