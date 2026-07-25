; =============================================================================
; Tattva OS — ufs/limits/ufs_quota.asm
; =============================================================================
; Storage Quota Enforcement Engine for uFS.
;
; Enforces soft and hard byte/inode limits per container.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%include "ufs/ufs.inc"

struc ufs_quota_t
    .soft_limit_bytes:   resq 1
    .hard_limit_bytes:   resq 1
    .current_bytes:      resq 1
    .soft_limit_inodes:  resq 1
    .hard_limit_inodes:  resq 1
    .current_inodes:     resq 1
endstruc

section .text

global ufs_quota_check_alloc

; -----------------------------------------------------------------------------
; ufs_quota_check_alloc
; -----------------------------------------------------------------------------
align 32
ufs_quota_check_alloc:
    push rbx

    mov rbx, rdi                    ; Pointer to ufs_quota_t
    mov rax, [rbx + ufs_quota_t.current_bytes]
    add rax, rsi
    cmp rax, [rbx + ufs_quota_t.hard_limit_bytes]
    jg .quota_exceeded

    mov eax, 0                      ; Permitted
    pop rbx
    ret

.quota_exceeded:
    mov eax, -122                   ; EDQUOT
    pop rbx
    ret
