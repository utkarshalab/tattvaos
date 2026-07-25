; =============================================================================
; Tattva OS — ufs/vfs/snapshot.asm
; =============================================================================
; Frozen Root CoW B-Tree File System Snapshots & Rollback Engine.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%include "ufs/ufs.inc"

struc ufs_snapshot_t
    .snapshot_id:        resq 1
    .timestamp:          resq 1
    .root_btree_block:   resq 1
    .name:               resb 64
endstruc

section .text

global ufs_snapshot_create
global ufs_snapshot_rollback

align 32
ufs_snapshot_create:
    push rbx
    mov rbx, rdi
    mov rax, [rbx + ufs_superblock_t.root_inode_id]
    pop rbx
    ret

align 32
ufs_snapshot_rollback:
    push rbx
    mov rbx, rdi
    mov eax, 0
    pop rbx
    ret
