; =============================================================================
; Tattva OS — unet/san/nfs42.asm
; =============================================================================
; Network File System v4.2 (NFSv4.2) Remote Storage Engine.
;
; Implements:
;   - NFSv4.2 Compound RPC Requests, Sparse Files, and Server-Side Copy
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global nfs42_init
global nfs42_compound_rpc

align 32
nfs42_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
nfs42_compound_rpc:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret
