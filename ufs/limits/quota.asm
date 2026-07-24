; =============================================================================
; Tattva OS — ufs/limits/quota.asm
; =============================================================================
; Storage Quota Enforcement Engine.
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

align 32
ufs_quota_check_alloc:
    push rbx
    mov rbx, rdi
    mov rax, [rbx + ufs_quota_t.current_bytes]
    add rax, rsi
    cmp rax, [rbx + ufs_quota_t.hard_limit_bytes]
    jg .quota_exceeded

    mov eax, 0
    pop rbx
    ret

.quota_exceeded:
    mov eax, -122
    pop rbx
    ret
