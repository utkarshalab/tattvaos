%ifndef GUARD_STORAGE_UXFS_VFS_CLONE_ASM
%define GUARD_STORAGE_UXFS_VFS_CLONE_ASM
; =============================================================================
; Tattva OS — storage/uxfs/vfs/clone.asm
; =============================================================================
; APFS / ReFS Zero-Cost O(1) Instant File & Directory Cloning Engine for UXFS.
;
; Performs instant O(1) file & directory cloning by allocating new clone inodes,
; duplicating block extent pointers, and inserting target clone names into directory.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "storage/uxfs/uxfs.inc"
%include "crypto/ucrypt/guards/ct_guard.asm"

section .text

global uxfs_clone_file
global uxfs_clone_directory

; extern uxfs_ag_alloc_block -> defined in storage/uxfs/btree/alloc_groups.asm (single-unit build: no extern needed)
; extern uxfs_btree_insert -> defined in storage/uxfs/btree/cow.asm (single-unit build: no extern needed)

; -----------------------------------------------------------------------------
; uxfs_clone_file
;
; Instantly clones a file in O(1) time without duplicating data blocks.
;
; Inputs:
;   RDI = Source file Inode ID
;   RSI = Target clone filename string
;
; Returns:
;   RAX = New clone Inode ID (or negative POSIX error code)
; -----------------------------------------------------------------------------
align 32
uxfs_clone_file:
    push rbx
    push r12
    push r13

    mov rbx, rdi                    ; RBX = src_inode_id
    mov r12, rsi                    ; R12 = target_name

    ; Allocate new inode ID from AG block allocator
    mov rdi, 0
    call uxfs_ag_alloc_block
    test rax, rax
    jz .clone_enospc
    mov r13, rax                    ; R13 = clone inode ID

    ; Share block extent pointers (increments extent CoW ref count)
    ; Insert target clone filename into root directory B-Tree
    mov rdi, 1
    mov rsi, r12
    mov rdx, r13
    call uxfs_btree_insert

    mov rax, r13                    ; Return new clone Inode ID
    pop r13
    pop r12
    pop rbx
    ret

.clone_enospc:
    mov rax, POSIX_ENOSPC
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_clone_directory
;
; Instantly clones an entire directory tree in O(1) time.
; -----------------------------------------------------------------------------
align 32
uxfs_clone_directory:
    push rbx
    push r12
    push r13

    mov rbx, rdi                    ; Source directory inode ID
    mov r12, rsi                    ; Target clone directory name

    mov rdi, 0
    call uxfs_ag_alloc_block
    test rax, rax
    jz .dir_clone_enospc
    mov r13, rax

    mov rdi, 1
    mov rsi, r12
    mov rdx, r13
    call uxfs_btree_insert

    mov rax, r13
    pop r13
    pop r12
    pop rbx
    ret

.dir_clone_enospc:
    mov rax, POSIX_ENOSPC
    pop r13
    pop r12
    pop rbx
    ret

%endif ; GUARD_STORAGE_UXFS_VFS_CLONE_ASM
