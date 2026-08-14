; =============================================================================
; Tattva OS — storage/uxfs/journal/journal.asm
; =============================================================================
; ext4 Fast-Commit & Write-Ahead Logging (WAL) Transaction Journal.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%include "storage/uxfs/uxfs.inc"

%define UXFS_WAL_MAGIC               0x4A4F5552
%define UXFS_WAL_BLOCK_DESCRIPTOR    1
%define UXFS_WAL_BLOCK_COMMIT        2
%define UXFS_WAL_BLOCK_REVOKE        3

struc uxfs_journal_block_t
    .magic:             resd 1
    .block_type:        resd 1
    .sequence:          resq 1
    .block_count:       resd 1
    .checksum:          resd 1
endstruc

section .data
align 8
global uxfs_journal_current_seq
uxfs_journal_current_seq: dq 1

section .text

global uxfs_journal_start_tx
global uxfs_journal_commit_tx
global uxfs_journal_replay

; extern ucmp_crc32_calc -> defined in lib/ucmp/checksum/crc32.asm (single-unit build: no extern needed)

align 32
uxfs_journal_start_tx:
    push rbx
    mov rbx, [uxfs_journal_current_seq]
    inc qword [uxfs_journal_current_seq]
    mov rax, rbx
    pop rbx
    ret

align 32
uxfs_journal_commit_tx:
    push rbx
    mov rbx, rdi
    mov dword [rbx + uxfs_journal_block_t.magic], UXFS_WAL_MAGIC
    mov dword [rbx + uxfs_journal_block_t.block_type], UXFS_WAL_BLOCK_COMMIT
    mov [rbx + uxfs_journal_block_t.sequence], rsi

    mov rdi, 0xFFFFFFFF
    mov rsi, rbx
    mov rdx, 4096
    call ucmp_crc32_calc
    mov dword [rbx + uxfs_journal_block_t.checksum], eax

    mov eax, 0
    pop rbx
    ret

align 32
uxfs_journal_replay:
    push rbx
    push r12
    push r13

    mov rbx, rdi
    mov r12, rsi
    xor r13, r13

.replay_loop:
    test r12, r12
    jz .done_replay

    cmp dword [rbx + uxfs_journal_block_t.magic], UXFS_WAL_MAGIC
    jne .corrupt_tx

    cmp dword [rbx + uxfs_journal_block_t.block_type], UXFS_WAL_BLOCK_COMMIT
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
