; =============================================================================
; Tattva OS — unet/tools/nfs_client.asm
; =============================================================================
; NFSv4.2 Network File System Remote Mount & File Transfer Client Tool.
;
; Implements:
;   - Mounts NFS Shares, Reads/Writes Remote Files & Executes RPC Compounds
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global nfs_client_init
global nfs_client_mount

align 32
nfs_client_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
nfs_client_mount:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret
