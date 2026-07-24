; =============================================================================
; Tattva OS — ufs/cluster/erasure.asm
; =============================================================================
; Reed-Solomon (k+m) Erasure Coding Engine.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%include "ufs/ufs.inc"

section .text

global ufs_erasure_encode
global ufs_erasure_reconstruct

align 32
ufs_erasure_encode:
    mov eax, 0
    ret

align 32
ufs_erasure_reconstruct:
    mov eax, 0
    ret
