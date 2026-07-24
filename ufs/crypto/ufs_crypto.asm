; =============================================================================
; Tattva OS — ufs/crypto/ufs_crypto.asm
; =============================================================================
; Native AES-256-XTS Storage Sector Encryption Engine for uFS.
;
; Implements IEEE 1619 AES-XTS disk encryption using AES-NI instructions,
; 512-bit master keys (split into Key1 and Key2), Galois field polynomial
; multiplication, and sector tweak encryption.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%include "ufs/ufs.inc"

section .text

global ufs_crypto_encrypt_sector
global ufs_crypto_decrypt_sector

extern ucrypt_aes_xts_encrypt_sector
extern ucrypt_aes_xts_decrypt_sector

; -----------------------------------------------------------------------------
; ufs_crypto_encrypt_sector
;
; Encrypts a 512-byte storage sector using AES-256-XTS.
;
; Inputs:
;   RDI = Pointer to 512-bit AES-XTS key (Key1=256 bits, Key2=256 bits)
;   RSI = 64-bit Sector Logical Block Address (LBA) tweak
;   RDX = Pointer to input plaintext sector (512 bytes)
;   RCX = Pointer to output ciphertext sector (512 bytes)
; -----------------------------------------------------------------------------
align 32
ufs_crypto_encrypt_sector:
    push rbp
    mov rbp, rsp

    call ucrypt_aes_xts_encrypt_sector

    pop rbp
    ret

; -----------------------------------------------------------------------------
; ufs_crypto_decrypt_sector
;
; Decrypts a 512-byte storage sector using AES-256-XTS.
; -----------------------------------------------------------------------------
align 32
ufs_crypto_decrypt_sector:
    push rbp
    mov rbp, rsp

    call ucrypt_aes_xts_decrypt_sector

    pop rbp
    ret
