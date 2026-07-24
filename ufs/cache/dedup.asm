; =============================================================================
; Tattva OS — ufs/cache/dedup.asm
; =============================================================================
; BLAKE3 Block-Level Deduplication Engine.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%include "ufs/ufs.inc"

%define UFS_DEDUP_TABLE_SLOTS       8192

struc ufs_dedup_entry_t
    .blake3_hash:       resb 32
    .physical_block_id: resq 1
    .ref_count:         resq 1
endstruc

section .data
align 16
global ufs_dedup_table
ufs_dedup_table: times UFS_DEDUP_TABLE_SLOTS * ufs_dedup_entry_t_size db 0

section .text

global ufs_dedup_init
global ufs_dedup_query
global ufs_dedup_insert

align 32
ufs_dedup_init:
    push rdi
    push rcx
    push rax

    lea rdi, [ufs_dedup_table]
    mov rcx, UFS_DEDUP_TABLE_SLOTS * ufs_dedup_entry_t_size
    xor al, al
    rep stosb

    pop rax
    pop rcx
    pop rdi
    ret

align 32
ufs_dedup_query:
    push rbx
    mov rbx, [rdi]
    and rbx, (UFS_DEDUP_TABLE_SLOTS - 1)
    imul rbx, rbx, ufs_dedup_entry_t_size
    lea rbx, [ufs_dedup_table + rbx]
    mov rax, [rbx + ufs_dedup_entry_t.physical_block_id]
    pop rbx
    ret

align 32
ufs_dedup_insert:
    push rbx
    mov rbx, [rdi]
    and rbx, (UFS_DEDUP_TABLE_SLOTS - 1)
    imul rbx, rbx, ufs_dedup_entry_t_size
    lea rbx, [ufs_dedup_table + rbx]
    mov [rbx + ufs_dedup_entry_t.physical_block_id], rsi
    mov qword [rbx + ufs_dedup_entry_t.ref_count], 1
    pop rbx
    ret
