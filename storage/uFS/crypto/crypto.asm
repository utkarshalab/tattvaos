; =============================================================================
; Tattva OS — ufs/crypto/crypto.asm
; =============================================================================
; Native AES-256-XTS Storage Sector Encryption Engine.
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

align 32
ufs_crypto_gf_mul_alpha:
    push rbx
    pextrq rax, xmm0, 1
    pextrq rbx, xmm0, 0
    bt rax, 63
    setc cl
    shld rax, rbx, 1
    shl rbx, 1
    test cl, cl
    jz .no_reduction
    xor rbx, 0x87

.no_reduction:
    pinsrq xmm0, rbx, 0
    pinsrq xmm0, rax, 1
    pop rbx
    ret

align 32
ufs_crypto_encrypt_sector:
    push rbp
    mov rbp, rsp
    call ucrypt_aes_xts_encrypt_sector
    pop rbp
    ret

align 32
ufs_crypto_decrypt_sector:
    push rbp
    mov rbp, rsp
    call ucrypt_aes_xts_decrypt_sector
    pop rbp
    ret
