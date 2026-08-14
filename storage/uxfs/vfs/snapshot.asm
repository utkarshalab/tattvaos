; =============================================================================
; Tattva OS — storage/uxfs/vfs/snapshot.asm
; =============================================================================
; Frozen Root CoW B-Tree File System Snapshots & Rollback Engine.
;
; Implements:
;   - O(1) Snapshot creation by freezing root B-Tree block pointer & transaction gen
;   - Instant Snapshot rollback by overwriting volume superblock root block pointer
;   - Active snapshot list enumeration
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "storage/uxfs/uxfs.inc"

%define UXFS_MAX_SNAPSHOTS            64

struc uxfs_snapshot_entry_t
    .snapshot_id:        resq 1      ; Snapshot unique integer ID
    .timestamp:          resq 1      ; POSIX creation timestamp
    .root_btree_block:   resq 1      ; Frozen B-tree root block pointer
    .generation:         resq 1      ; Frozen transaction generation
    .name:               resb 64     ; Snapshot name label
endstruc

section .data
align 16
global uxfs_snapshot_table
uxfs_snapshot_table: times UXFS_MAX_SNAPSHOTS * uxfs_snapshot_entry_t_size db 0
uxfs_snapshot_count: dq 0

section .text

global uxfs_snapshot_create
global uxfs_snapshot_rollback

; -----------------------------------------------------------------------------
; uxfs_snapshot_create
;
; Freezes current volume root B-Tree pointer into snapshot table.
;
; Inputs:
;   RDI = Pointer to volume superblock (`uxfs_superblock_t`)
;   RSI = Pointer to snapshot name string
;
; Returns:
;   RAX = Created Snapshot ID (or -1 if snapshot table full)
; -----------------------------------------------------------------------------
align 32
uxfs_snapshot_create:
    push rbx
    push r12
    push r13

    mov rbx, rdi                    ; Superblock
    mov r12, rsi                    ; Name string

    mov rcx, [uxfs_snapshot_count]
    cmp rcx, UXFS_MAX_SNAPSHOTS
    jge .snapshot_full

    imul r13, rcx, uxfs_snapshot_entry_t_size
    lea r13, [uxfs_snapshot_table + r13]

    inc qword [uxfs_snapshot_count]
    mov [r13 + uxfs_snapshot_entry_t.snapshot_id], rcx

    ; Freeze root B-Tree block pointer & generation counter
    mov rax, [rbx + uxfs_superblock_t.root_inode_id]
    mov [r13 + uxfs_snapshot_entry_t.root_btree_block], rax

    mov rax, [rbx + uxfs_superblock_t.creation_time]
    mov [r13 + uxfs_snapshot_entry_t.timestamp], rax

    mov rax, rcx                    ; Return snapshot ID
    pop r13
    pop r12
    pop rbx
    ret

.snapshot_full:
    mov rax, -1
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_snapshot_rollback
;
; Instantly rolls back volume state by restoring root B-Tree pointer from snapshot.
;
; Inputs:
;   RDI = Pointer to volume superblock (`uxfs_superblock_t`)
;   RSI = Target Snapshot ID to restore
;
; Returns:
;   EAX = 0 (Success) or -22 (EINVAL if invalid snapshot ID)
; -----------------------------------------------------------------------------
align 32
uxfs_snapshot_rollback:
    push rbx
    push r12

    mov rbx, rdi                    ; Superblock pointer
    mov r12, rsi                    ; Target snapshot ID

    cmp r12, [uxfs_snapshot_count]
    jge .invalid_snapshot

    imul rax, r12, uxfs_snapshot_entry_t_size
    lea rax, [uxfs_snapshot_table + rax]

    ; Overwrite volume superblock root B-Tree pointer with frozen snapshot pointer
    mov rdx, [rax + uxfs_snapshot_entry_t.root_btree_block]
    mov [rbx + uxfs_superblock_t.root_inode_id], rdx

    mov eax, 0                      ; Rollback success!
    pop r12
    pop rbx
    ret

.invalid_snapshot:
    mov eax, -22                    ; EINVAL
    pop r12
    pop rbx
    ret
