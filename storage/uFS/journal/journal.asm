; =============================================================================
; Tattva OS — ufs/journal/journal.asm
; =============================================================================
; ext4 Fast-Commit & Write-Ahead Logging (WAL) Transaction Journal.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%include "ufs/ufs.inc"

%define UFS_WAL_MAGIC               0x4A4F5552
%define UFS_WAL_BLOCK_DESCRIPTOR    1
%define UFS_WAL_BLOCK_COMMIT        2
%define UFS_WAL_BLOCK_REVOKE        3

struc ufs_journal_block_t
    .magic:             resd 1
    .block_type:        resd 1
    .sequence:          resq 1
    .block_count:       resd 1
    .checksum:          resd 1
endstruc

section .data
align 8
global ufs_journal_current_seq
ufs_journal_current_seq: dq 1

section .text

global ufs_journal_start_tx
global ufs_journal_commit_tx
global ufs_journal_replay

extern ucmp_crc32_calc

align 32
ufs_journal_start_tx:
    push rbx
    mov rbx, [ufs_journal_current_seq]
    inc qword [ufs_journal_current_seq]
    mov rax, rbx
    pop rbx
    ret

align 32
ufs_journal_commit_tx:
    push rbx
    mov rbx, rdi
    mov dword [rbx + ufs_journal_block_t.magic], UFS_WAL_MAGIC
    mov dword [rbx + ufs_journal_block_t.block_type], UFS_WAL_BLOCK_COMMIT
    mov [rbx + ufs_journal_block_t.sequence], rsi

    mov rdi, 0xFFFFFFFF
    mov rsi, rbx
    mov rdx, 4096
    call ucmp_crc32_calc
    mov dword [rbx + ufs_journal_block_t.checksum], eax

    mov eax, 0
    pop rbx
    ret

align 32
ufs_journal_replay:
    push rbx
    push r12
    push r13

    mov rbx, rdi
    mov r12, rsi
    xor r13, r13

.replay_loop:
    test r12, r12
    jz .done_replay

    cmp dword [rbx + ufs_journal_block_t.magic], UFS_WAL_MAGIC
    jne .corrupt_tx

    cmp dword [rbx + ufs_journal_block_t.block_type], UFS_WAL_BLOCK_COMMIT
    jne .next_tx_block

    inc r13

.next_tx_block:
    add rbx, 4096
    dec r12
    jmp .replay_loop

.done_replay:
    mov eax, r13d
    pop r13
    pop r12
    pop rbx
    ret

.corrupt_tx:
    mov eax, -1
    pop r13
    pop r12
    pop rbx
    ret
