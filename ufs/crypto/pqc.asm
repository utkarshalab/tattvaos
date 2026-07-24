; =============================================================================
; Tattva OS — ufs/crypto/pqc.asm
; =============================================================================
; Post-Quantum Hybrid Disk Key Encapsulation (ML-KEM-1024 + AES-XTS).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%include "ufs/ufs.inc"

section .text

global ufs_pqc_encapsulate_key
global ufs_pqc_decapsulate_key

extern upqc_kyber_encapsulate
extern upqc_kyber_decapsulate

align 32
ufs_pqc_encapsulate_key:
    push rbp
    mov rbp, rsp
    call upqc_kyber_encapsulate
    pop rbp
    ret

align 32
ufs_pqc_decapsulate_key:
    push rbp
    mov rbp, rsp
    call upqc_kyber_decapsulate
    pop rbp
    ret
