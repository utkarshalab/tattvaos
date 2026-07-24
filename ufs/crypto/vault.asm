; =============================================================================
; Tattva OS — ufs/crypto/vault.asm
; =============================================================================
; Encrypted Vault Key Manager (Argon2id + AES-KWP).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%include "ufs/ufs.inc"

section .text

global ufs_vault_derive_key
global ufs_vault_wrap_master_key

extern ukdf_argon2id
extern ucrypt_aes_kw_wrap

align 32
ufs_vault_derive_key:
    push rbp
    mov rbp, rsp
    call ukdf_argon2id
    pop rbp
    ret

align 32
ufs_vault_wrap_master_key:
    push rbp
    mov rbp, rsp
    call ucrypt_aes_kw_wrap
    pop rbp
    ret
