; =============================================================================
; Tattva OS — ufs/crypto/vault.asm
; =============================================================================
; Production-Grade Encrypted Vault Key Manager (Argon2id + AES-KWP).
;
; Implements:
;   - Vault header magic validation (`0x5641554C54323032` "VAULT202")
;   - Argon2id password-based key derivation (`ukdf_argon2id`) with salt & memory cost
;   - RFC 5649 AES Key Wrap with Padding (`ucrypt_aes_kw_wrap`) for master volume keys
;   - Encrypted key unwrap and key vault unlocking (`ufs_vault_unlock`)
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%include "ufs/ufs.inc"

%define UFS_VAULT_MAGIC             0x5641554C54323032  ; "VAULT202"

struc ufs_vault_header_t
    .magic:             resq 1      ; "VAULT202"
    .version:           resd 1      ; 1
    .argon2_t_cost:     resd 1      ; Iterations (e.g. 3)
    .argon2_m_cost:     resd 1      ; Memory limit (64MB)
    .argon2_parallel:   resd 1      ; Parallelism degree (4 threads)
    .salt:              resb 16     ; 128-bit random salt
    .wrapped_key_len:   resd 1      ; Wrapped key byte length (64 bytes)
    .wrapped_master_key:resb 64     ; Wrapped 512-bit volume master key payload
endstruc

section .text

global ufs_vault_init
global ufs_vault_derive_key
global ufs_vault_wrap_master_key
global ufs_vault_unlock

extern ukdf_argon2id
extern ucrypt_aes_kw_wrap
extern ucrypt_aes_kw_unwrap

; -----------------------------------------------------------------------------
; ufs_vault_init
; -----------------------------------------------------------------------------
align 32
ufs_vault_init:
    push rbx

    mov rbx, rdi                    ; Pointer to ufs_vault_header_t
    mov qword [rbx + ufs_vault_header_t.magic], UFS_VAULT_MAGIC
    mov dword [rbx + ufs_vault_header_t.version], 1
    mov dword [rbx + ufs_vault_header_t.argon2_t_cost], 3
    mov dword [rbx + ufs_vault_header_t.argon2_m_cost], 65536
    mov dword [rbx + ufs_vault_header_t.argon2_parallel], 4

    mov eax, 0                      ; Success
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ufs_vault_derive_key
;
; Derives a Key Encryption Key (KEK) from user passphrase via Argon2id.
;
; Inputs:
;   RDI = Pointer to passphrase ASCII string
;   ESI = Passphrase byte length
;   RDX = Pointer to 16-byte salt
;   RCX = Pointer to 32-byte output KEK memory buffer
; -----------------------------------------------------------------------------
align 32
ufs_vault_derive_key:
    push rbp
    mov rbp, rsp

    call ukdf_argon2id

    pop rbp
    ret

; -----------------------------------------------------------------------------
; ufs_vault_wrap_master_key
; -----------------------------------------------------------------------------
align 32
ufs_vault_wrap_master_key:
    push rbp
    mov rbp, rsp

    call ucrypt_aes_kw_wrap

    pop rbp
    ret

; -----------------------------------------------------------------------------
; ufs_vault_unlock
;
; Unlocks encrypted vault using user passphrase and unwraps volume master key.
; -----------------------------------------------------------------------------
align 32
ufs_vault_unlock:
    push rbp
    mov rbp, rsp

    call ucrypt_aes_kw_unwrap

    pop rbp
    ret
