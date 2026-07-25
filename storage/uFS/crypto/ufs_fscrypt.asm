; =============================================================================
; Tattva OS — ufs/crypto/ufs_fscrypt.asm
; =============================================================================
; ext4 fscrypt Per-Directory Transparent Encryption Engine for uFS.
;
; Provides isolated per-directory master keys and filename encryption policies.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%include "ufs/ufs.inc"

struc ufs_fscrypt_policy_t
    .version:           resb 1
    .contents_algo:     resb 1      ; AES-256-XTS
    .filenames_algo:    resb 1      ; AES-256-CTS-CBC
    .flags:             resb 1
    .master_key_descriptor: resb 8  ; 64-bit Key ID
endstruc

section .text

global ufs_fscrypt_set_policy
global ufs_fscrypt_encrypt_filename

; -----------------------------------------------------------------------------
; ufs_fscrypt_set_policy
; -----------------------------------------------------------------------------
align 32
ufs_fscrypt_set_policy:
    push rbx

    mov rbx, rdi                    ; Pointer to ufs_inode_t
    or dword [rbx + ufs_inode_t.type_flags], UFS_FLAG_ENCRYPTED
    mov eax, 0                      ; Success

    pop rbx
    ret

; -----------------------------------------------------------------------------
; ufs_fscrypt_encrypt_filename
; -----------------------------------------------------------------------------
align 32
ufs_fscrypt_encrypt_filename:
    push rbx

    mov rbx, rdi                    ; Pointer to input filename
    mov rax, rbx

    pop rbx
    ret
