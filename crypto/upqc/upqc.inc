; =============================================================================
; Tattva OS — crypto/upqc/upqc.inc
; =============================================================================
; Master Unified Post-Quantum Cryptography (PQC) Schemas & Algorithm IDs.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef CRYPTO_UPQC_UPQC_INC
%define CRYPTO_UPQC_UPQC_INC

; PQC Algorithm IDs
UPQC_ALGO_DILITHIUM     equ 1       ; NIST ML-DSA (CRYSTALS-Dilithium Signatures)
UPQC_ALGO_KYBER         equ 2       ; NIST ML-KEM (CRYSTALS-Kyber Key Encapsulation)
UPQC_ALGO_FALCON        equ 3       ; NIST FALCON (Lattice-based Signatures)
UPQC_ALGO_SPHINCS       equ 4       ; NIST SPHINCS+ (Stateless Hash-based Signatures)

; -----------------------------------------------------------------------------
; Unified PQC Context Structure (256 bytes)
; -----------------------------------------------------------------------------
struc upqc_ctx_t
    .algo_id        resd 1          ; +00: PQC Algorithm ID (Dilithium, Kyber, FALCON...)
    .pubkey_ptr     resq 1          ; +04: Pointer to Public Key
    .pubkey_len     resd 1          ; +12: Public Key size
    .privkey_ptr    resq 1          ; +16: Pointer to Private Key
    .privkey_len    resd 1          ; +24: Private Key size
    .sig_ptr        resq 1          ; +28: Pointer to Signature / Ciphertext
    .sig_len        resd 1          ; +36: Signature / Ciphertext size
    .reserved       resq 26         ; +40..+256: L1 Cache Padding
endstruc

upqc_ctx_t_size equ 256

%endif ; CRYPTO_UPQC_UPQC_INC
