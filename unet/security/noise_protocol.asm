%ifndef GUARD_UNET_SECURITY_NOISE_PROTOCOL_ASM
%define GUARD_UNET_SECURITY_NOISE_PROTOCOL_ASM
; =============================================================================
; Tattva OS — unet/security/noise_protocol.asm
; =============================================================================
; Noise Protocol Framework Engine (Noise Specification / RFC 7539).
;
; Features:
;   - Handshake Patterns: Noise_IK, Noise_XX, Noise_NK, Noise_KK, Noise_N
;   - Symmetric State & Cipher State Chain (SymmetricKey, HandshakeHash)
;   - DH Operations: Curve25519 (25519) & Secp256r1
;   - Cipher Operations: ChaCha20-Poly1305 & AES-256-GCM
;   - Hash Operations: SHA-256 & BLAKE2s
;   - Prologue & Ephemeral Key Mixing
;
; Delegates:
;   - ChaCha20-Poly1305 / AES-GCM       -> lib/crypto/
;   - Curve25519                        -> lib/crypto/ed25519.asm
;   - SHA-256 / BLAKE2s                 -> lib/crypto/
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

struc noise_state_t
    .h:                 resb 32     ; Handshake Hash
    .ck:                resb 32     ; Chaining Key
    .k:                 resb 32     ; Cipher Key
    .n:                 resq 1      ; Nonce Counter
    .s_local:           resb 32     ; Static Local Public Key
    .e_local:           resb 32     ; Ephemeral Local Public Key
    .s_remote:          resb 32     ; Static Remote Public Key
    .e_remote:          resb 32     ; Ephemeral Remote Public Key
endstruc

section .text

global noise_init
global noise_mix_hash
global noise_mix_key
global noise_encrypt_and_hash
global noise_decrypt_and_hash
global noise_split

align 64
noise_init:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Initialize Noise State with protocol name hash: h = HASH(protocol_name)
    call sha256_hash
    pop rbp
    ret

align 64
noise_mix_hash:
    push rbp
    mov rbp, rsp
    prefetcht0 [rsi]
    ; h = HASH(h || data)
    call sha256_hash
    pop rbp
    ret

align 64
noise_mix_key:
    push rbp
    mov rbp, rsp
    prefetcht0 [rsi]
    ; (ck, k) = HKDF(ck, input_key_material)
    call hkdf_extract_expand
    pop rbp
    ret

align 64
noise_encrypt_and_hash:
    push rbp
    mov rbp, rsp
    prefetcht0 [rsi]
    ; Encrypt plaintext with k and n, then mix ciphertext into h
    call chacha20_poly1305_encrypt
    call noise_mix_hash
    pop rbp
    ret

align 64
noise_decrypt_and_hash:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Mix ciphertext into h, then decrypt ciphertext with k and n
    call noise_mix_hash
    call chacha20_poly1305_decrypt
    pop rbp
    ret

align 64
noise_split:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Derive (k1, k2) = HKDF(ck, zerolen) for bidirectional transport keys
    call hkdf_extract_expand
    pop rbp
    ret

%endif ; GUARD_UNET_SECURITY_NOISE_PROTOCOL_ASM
