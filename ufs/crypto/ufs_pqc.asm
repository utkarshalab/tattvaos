; =============================================================================
; Tattva OS — ufs/crypto/ufs_pqc.asm
; =============================================================================
; Post-Quantum Hybrid Disk Key Encapsulation (ML-KEM-1024 + AES-256-XTS).
;
; Encapsulates volume master keys using NIST FIPS 203 ML-KEM-1024 (Kyber-1024)
; lattice cryptography for quantum-resistant disk encryption header protection.
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

; -----------------------------------------------------------------------------
; ufs_pqc_encapsulate_key
; -----------------------------------------------------------------------------
align 32
ufs_pqc_encapsulate_key:
    push rbp
    mov rbp, rsp

    call upqc_kyber_encapsulate

    pop rbp
    ret

; -----------------------------------------------------------------------------
; ufs_pqc_decapsulate_key
; -----------------------------------------------------------------------------
align 32
ufs_pqc_decapsulate_key:
    push rbp
    mov rbp, rsp

    call upqc_kyber_decapsulate

    pop rbp
    ret
