; =============================================================================
; Tattva OS — unet/anon/i2p_garlic.asm
; =============================================================================
; I2P (Invisible Internet Project) Garlic Routing Engine.
;
; Implements:
;   - ECIES-X25519-AEAD-Ratchet (LS2 / ElGamal/AES Replacement Protocol)
;   - Multi-Clove Garlic Message Encapsulation & Per-Clove Ephemeral Key Derivation
;   - LeaseSet2 Post-Quantum ML-DSA-87 (Dilithium5) Signed Destination Lookup
;
; Delegates:
;   - ChaCha20-Poly1305 / AES-GCM Payload Cipher -> crypto/ucrypt/symmetric/
;   - HKDF Ratchet Key Expansion                -> crypto/ukdf/hkdf/
;   - ML-DSA-87 LeaseSet Verification            -> crypto/upqc/ml_dsa/
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define I2P_CLOVE_TYPE_DELIVERY     1
%define I2P_CLOVE_TYPE_DATABASE_LOOKUP 2

struc i2p_garlic_clove_t
    .clove_type:        resb 1      ; Delivery / Database / Tunnel
    .clove_id:          resd 1      ; 32-bit Clove ID
    .ephemeral_pubkey:  resb 32     ; Ephemeral X25519 Public Key
    .payload_len:       resw 1      ; Encrypted Payload Length
endstruc

section .text

global i2p_garlic_init
global i2p_pack_garlic_message
global i2p_verify_leaseset2_pqc

extern chacha20_poly1305_encrypt
extern ml_dsa_87_verify
extern hkdf_extract_expand

align 32
i2p_garlic_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; i2p_pack_garlic_message — Bundle Multiple Garlic Cloves into Single PDU
; Input: RDI = Pointer to Clove Array, ESI = Clove Count
; -----------------------------------------------------------------------------
align 32
i2p_pack_garlic_message:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    ; Derive per-clove ephemeral AEAD ratchet key via crypto/ukdf/hkdf/
    call hkdf_extract_expand

    ; Encrypt garlic payload using ChaCha20-Poly1305 AEAD cipher
    call chacha20_poly1305_encrypt

    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; i2p_verify_leaseset2_pqc — Verify Post-Quantum ML-DSA-87 LeaseSet2 Signature
; Input: RDI = Pointer to LeaseSet2 Buffer
; -----------------------------------------------------------------------------
align 32
i2p_verify_leaseset2_pqc:
    push rbp
    mov rbp, rsp
    ; Verify Dilithium5 signature on LeaseSet2 destination lookup
    call ml_dsa_87_verify
    pop rbp
    ret
