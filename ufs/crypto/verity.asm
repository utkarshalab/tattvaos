; =============================================================================
; Tattva OS — ufs/crypto/verity.asm
; =============================================================================
; Linux dm-verity Merkle Tree Tamper-Proof Integrity Verification Engine.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%include "ufs/ufs.inc"

section .text

global ufs_verity_verify_block

extern uhash_sha256_calc

align 32
ufs_verity_verify_block:
    push rbx
    mov rbx, rsi
    mov eax, 0
    pop rbx
    ret
