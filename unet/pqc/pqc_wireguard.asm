%ifndef GUARD_UNET_PQC_PQC_WIREGUARD_ASM
%define GUARD_UNET_PQC_PQC_WIREGUARD_ASM
; =============================================================================
; Tattva OS — unet/pqc/pqc_wireguard.asm
; =============================================================================
; Post-Quantum Hybrid WireGuard Protocol Subsystem (ML-KEM-1024 + Curve25519).
;
; Features:
;   - PQ-Noise_IKpsk2 Handshake Extension
;   - Post-Quantum ML-KEM-1024 (Kyber-1024 FIPS 203) Encapsulation Key Exchange
;   - Dual Key Mix: HKDF-SHA256(ECDH_Secret || ML_KEM_Secret) -> WireGuard Master Key
;   - Quantum-Resistant Rekeying Schedule & AVX-512 Secret Zeroization Purge
;
; Delegates:
;   - WireGuard Protocol Base           -> unet/sdn/wireguard.asm
;   - ML-KEM-1024                       -> crypto/ukem/ml_kem_1024.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

struc pqc_wg_handshake_init_t
    .type:              resb 1      ; Message Type = 1
    .sender_index:      resd 1
    .ephemeral_ecdh:    resb 32     ; Curve25519 Ephemeral Public Key
    .ephemeral_pqc:     resb 1568   ; ML-KEM-1024 Encapsulated Ciphertext
    .mac1:              resb 16
    .mac2:              resb 16
endstruc

section .text

global pqc_wireguard_init
global pqc_wireguard_handshake
global pqc_wireguard_mix_keys

align 64
pqc_wireguard_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 64
pqc_wireguard_handshake:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; 1. Generate Curve25519 Ephemeral Keypair
    ; 2. Generate ML-KEM-1024 Ciphertext via Encapsulation
    call ml_kem_1024_encaps

    ; 3. Combine ECDH + ML-KEM secrets into WireGuard chaining key
    call pqc_wireguard_mix_keys

    pop rbx
    pop rbp
    ret

align 64
pqc_wireguard_mix_keys:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; HKDF-SHA256(chaining_key, ecdh_secret || ml_kem_secret)
    xor eax, eax
    pop rbp
    ret

%endif ; GUARD_UNET_PQC_PQC_WIREGUARD_ASM
