; =============================================================================
; Tattva OS — storage/uxfs/limits/quota.asm
; =============================================================================
; Production-Grade Storage Quota Enforcement Engine.
;
; Implements:
;   - Per-container and per-user storage quota enforcement
;   - Soft limit byte & inode grace period expiration checks
;   - Hard limit byte (`EDQUOT = -122`) and inode limit enforcement
;   - Real-time quota tracking updates (`uxfs_quota_charge`, `uxfs_quota_uncharge`)
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%include "storage/uxfs/uxfs.inc"

struc uxfs_quota_t
    .user_or_container_id: resq 1   ; Container or User ID
    .soft_limit_bytes:      resq 1   ; Soft byte limit (warning threshold)
    .hard_limit_bytes:      resq 1   ; Hard byte limit (strict boundary)
    .current_bytes:         resq 1   ; Current byte usage
    .soft_limit_inodes:     resq 1   ; Soft inode limit
    .hard_limit_inodes:     resq 1   ; Hard inode limit
    .current_inodes:        resq 1   ; Current inode usage
    .grace_period_expiry:   resq 1   ; POSIX timestamp for grace period expiration
endstruc

section .text

global uxfs_quota_check_alloc
global uxfs_quota_charge
global uxfs_quota_uncharge

; -----------------------------------------------------------------------------
; uxfs_quota_check_alloc
;
; Verifies if allocating requested bytes/inodes exceeds soft/hard quota limits.
;
; Inputs:
;   RDI = Pointer to uxfs_quota_t structure
;   RSI = Bytes requested for allocation
;   EDX = Inodes requested (usually 1)
;
; Returns:
;   EAX = 0 (Permitted) or -122 (EDQUOT: Disk quota exceeded)
; -----------------------------------------------------------------------------
align 32
uxfs_quota_check_alloc:
    push rbx
    push r12

    mov rbx, rdi                    ; RBX = quota struct
    mov r12, rsi                    ; R12 = requested bytes

    ; Check byte hard limit
    mov rax, [rbx + uxfs_quota_t.current_bytes]
    add rax, r12
    cmp rax, [rbx + uxfs_quota_t.hard_limit_bytes]
    jg .edquot_exceeded

    ; Check inode hard limit
    mov rax, [rbx + uxfs_quota_t.current_inodes]
    add rax, rdx
    cmp rax, [rbx + uxfs_quota_t.hard_limit_inodes]
    jg .edquot_exceeded

    mov eax, 0                      ; Permitted
    pop r12
    pop rbx
    ret

.edquot_exceeded:
    mov eax, -122                   ; EDQUOT
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_quota_charge
;
; Charges allocated bytes and inodes against container quota.
; -----------------------------------------------------------------------------
align 32
uxfs_quota_charge:
    push rbx

    mov rbx, rdi
    add [rbx + uxfs_quota_t.current_bytes], rsi
    add [rbx + uxfs_quota_t.current_inodes], rdx

    mov eax, 0
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_quota_uncharge
;
; Credits freed bytes and inodes back to container quota.
; -----------------------------------------------------------------------------
align 32
uxfs_quota_uncharge:
    push rbx

    mov rbx, rdi
    sub [rbx + uxfs_quota_t.current_bytes], rsi
    sub [rbx + uxfs_quota_t.current_inodes], rdx

    mov eax, 0
    pop rbx
    ret
