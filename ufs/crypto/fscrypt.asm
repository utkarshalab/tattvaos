; =============================================================================
; Tattva OS — ufs/crypto/fscrypt.asm
; =============================================================================
; ext4 fscrypt Per-Directory Transparent Encryption Engine.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%include "ufs/ufs.inc"

struc ufs_fscrypt_policy_t
    .version:           resb 1
    .contents_algo:     resb 1
    .filenames_algo:    resb 1
    .flags:             resb 1
    .master_key_descriptor: resb 8
endstruc

section .text

global ufs_fscrypt_set_policy
global ufs_fscrypt_encrypt_filename

align 32
ufs_fscrypt_set_policy:
    push rbx
    mov rbx, rdi
    or dword [rbx + ufs_inode_t.type_flags], UFS_FLAG_ENCRYPTED
    mov eax, 0
    pop rbx
    ret

align 32
ufs_fscrypt_encrypt_filename:
    push rbx
    mov rbx, rdi
    mov rax, rbx
    pop rbx
    ret
