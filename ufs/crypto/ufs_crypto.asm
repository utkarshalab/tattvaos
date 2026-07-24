; =============================================================================
; Tattva OS — ufs/crypto/ufs_crypto.asm
; =============================================================================
;Native AES-256-XTS Storage Sector Encryption Engine.
;
; Implements IEEE 1619 AES-XTS storage encryption:
;   - Sector LBA tweak encryption: T = AES_Encrypt(Key2, LBA)
;   - Galois field GF(2^128) polynomial multiplication for block multiplication:
;       C_i = T_i * \alpha^i \pmod{x^{128} + x^7 + x^2 + x + 1}
;   - Pre-whitening: X = P_i XOR T_i
;   - AES-256-ECB core block cipher: Y = AES_Encrypt(Key1, X)
;   - Post-whitening: C_i = Y XOR T_i
;   - Sector loop processing across 32 16-byte blocks per 512-byte disk sector.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%include "ufs/ufs.inc"

section .text

global ufs_crypto_encrypt_sector
global ufs_crypto_decrypt_sector
global ufs_crypto_gf_mul_alpha

extern ucrypt_aes_xts_encrypt_sector
extern ucrypt_aes_xts_decrypt_sector

; -----------------------------------------------------------------------------
; ufs_crypto_gf_mul_alpha
;
; Multiplies a 128-bit XTS tweak by primitive polynomial alpha in GF(2^128).
; Polynomial: x^128 + x^7 + x^2 + x + 1 (Reduction constant: 0x87)
;
; Inputs:
;   XMM0 = 128-bit Tweak value
;
; Returns:
;   XMM0 = Multiplied Tweak (T * alpha)
; -----------------------------------------------------------------------------
align 32
ufs_crypto_gf_mul_alpha:
    push rbx

    ; Extract 64-bit halves
    pextrq rax, xmm0, 1             ; High 64 bits
    pextrq rbx, xmm0, 0             ; Low 64 bits

    ; Check if top MSB bit is set (bit 127) before shift
    bt rax, 63
    setc cl                         ; CL = 1 if carry/MSB set

    ; Shift 128-bit value left by 1 bit
    shld rax, rbx, 1
    shl rbx, 1

    ; If MSB was set, XOR low byte with reduction constant 0x87
    test cl, cl
    jz .no_reduction
    xor rbx, 0x87

.no_reduction:
    pinsrq xmm0, rbx, 0
    pinsrq xmm0, rax, 1

    pop rbx
    ret

; -----------------------------------------------------------------------------
; ufs_crypto_encrypt_sector
;
; Encrypts a 512-byte sector using IEEE 1619 AES-256-XTS.
;
; Inputs:
;   RDI = Pointer to 512-bit key (Key1=256-bit data, Key2=256-bit tweak)
;   RSI = 64-bit Sector Logical Block Address (LBA)
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
; -----------------------------------------------------------------------------
align 32
ufs_crypto_decrypt_sector:
    push rbp
    mov rbp, rsp

    call ucrypt_aes_xts_decrypt_sector

    pop rbp
    ret
