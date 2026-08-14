; =============================================================================
; Tattva OS — storage/uxfs/btree/alloc_groups.asm
; =============================================================================
; XFS-Grade Allocation Groups (AG) & Fast Hardware Bitmask Storage Allocator.
;
; Features:
;   - Multi-AG round-robin scanning across all 16 Allocation Groups
;   - Hardware 64-bit Bit-Scan Forward (`bsf` / `tzcnt`) for O(1) free block allocation
;   - Double-free bitmap protection (`lock btr` / `lock bts` verification)
;   - SMP lock-free thread safety with `lock` atomic instruction prefixes
;   - Dynamic CRC32 bitmap checksum updating via `ucmp_crc32_calc`
;   - Allocation Group statistics & status reporting (`uxfs_ag_get_stat`)
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "storage/uxfs/uxfs.inc"

%define UXFS_AG_MAX_GROUPS           16
%define UXFS_AG_BITMAP_QWORDS        64                  ; 4096 blocks per AG

struc uxfs_ag_descriptor_t
    .ag_id:             resd 1      ; Allocation Group ID (0..15)
    .total_blocks:      resd 1      ; Total blocks in group (4096)
    .free_blocks:       resd 1      ; Free block count
    .checksum:          resd 1      ; CRC32 bitmap checksum
    .bitmap:            resq UXFS_AG_BITMAP_QWORDS ; 4096-bit free/used bitmap
endstruc

section .data
align 16
global uxfs_ag_table
uxfs_ag_table: times UXFS_AG_MAX_GROUPS * uxfs_ag_descriptor_t_size db 0
uxfs_ag_last_alloc_id: dd 0

section .text

global uxfs_ag_init
global uxfs_ag_alloc_block
global uxfs_ag_free_block
global uxfs_ag_get_stat
global uxfs_ag_update_checksum

; extern ucmp_crc32_calc -> defined in lib/ucmp/checksum/crc32.asm (single-unit build: no extern needed)

; -----------------------------------------------------------------------------
; uxfs_ag_init
; -----------------------------------------------------------------------------
align 32
uxfs_ag_init:
    push rbx
    push rdi
    push rcx
    push rax

    lea rdi, [uxfs_ag_table]
    mov rcx, UXFS_AG_MAX_GROUPS * uxfs_ag_descriptor_t_size
    xor al, al
    rep stosb

    xor ecx, ecx
.ag_init_loop:
    cmp ecx, UXFS_AG_MAX_GROUPS
    jge .done_ag_init

    imul rax, rcx, uxfs_ag_descriptor_t_size
    lea rax, [uxfs_ag_table + rax]

    mov [rax + uxfs_ag_descriptor_t.ag_id], ecx
    mov dword [rax + uxfs_ag_descriptor_t.total_blocks], 4096
    mov dword [rax + uxfs_ag_descriptor_t.free_blocks], 4096

    mov rdi, 0xFFFFFFFF
    lea rsi, [rax + uxfs_ag_descriptor_t.bitmap]
    mov rdx, UXFS_AG_BITMAP_QWORDS * 8
    call ucmp_crc32_calc
    mov [rax + uxfs_ag_descriptor_t.checksum], eax

    inc ecx
    jmp .ag_init_loop

.done_ag_init:
    mov dword [uxfs_ag_last_alloc_id], 0
    pop rax
    pop rcx
    pop rdi
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_ag_alloc_block
;
; SMP Thread-Safe Hardware Bit-Scan (`bsf`) allocation with `lock bts`.
; -----------------------------------------------------------------------------
align 32
uxfs_ag_alloc_block:
    push rbx
    push r12
    push r13
    push r14

    mov eax, edi
    test eax, eax
    jnz .use_specified_ag

    mov eax, [uxfs_ag_last_alloc_id]

.use_specified_ag:
    mov r14d, UXFS_AG_MAX_GROUPS

.try_ag_loop:
    test r14d, r14d
    jz .alloc_enospc

    and eax, 0x0F

    imul rbx, rax, uxfs_ag_descriptor_t_size
    lea rbx, [uxfs_ag_table + rbx]

    mov ecx, [rbx + uxfs_ag_descriptor_t.free_blocks]
    test ecx, ecx
    jz .try_next_ag

    lea r12, [rbx + uxfs_ag_descriptor_t.bitmap]
    xor r13, r13

.scan_qword_loop:
    cmp r13, UXFS_AG_BITMAP_QWORDS
    jge .try_next_ag

    mov rax, [r12 + r13 * 8]
    not rax
    test rax, rax
    jnz .found_free_bit

    inc r13
    jmp .scan_qword_loop

.found_free_bit:
    bsf rcx, rax

    ; Atomic Lock-Free Bit-Set across CPU cores
    lock bts qword [r12 + r13 * 8], rcx
    jc .retry_bit_scan              ; If bit was acquired by another thread concurrently, retry!

    lock dec dword [rbx + uxfs_ag_descriptor_t.free_blocks]

    mov eax, [rbx + uxfs_ag_descriptor_t.ag_id]
    mov [uxfs_ag_last_alloc_id], eax

    shl rax, 12
    shl r13, 6
    add rax, r13
    add rax, rcx
    add rax, 1

    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.retry_bit_scan:
    jmp .scan_qword_loop

.try_next_ag:
    mov eax, [rbx + uxfs_ag_descriptor_t.ag_id]
    inc eax
    dec r14d
    jmp .try_ag_loop

.alloc_enospc:
    xor rax, rax
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_ag_free_block
;
; SMP Thread-Safe block deallocation with atomic `lock btr`.
; -----------------------------------------------------------------------------
align 32
uxfs_ag_free_block:
    push rbx
    push r12
    push r13

    mov rax, rdi
    dec rax
    js .invalid_lba

    mov r8, rax
    shr r8, 12
    cmp r8, UXFS_AG_MAX_GROUPS
    jge .invalid_lba

    imul rbx, r8, uxfs_ag_descriptor_t_size
    lea rbx, [uxfs_ag_table + rbx]

    and rax, 4095
    mov r12, rax
    shr r12, 6
    and rax, 63

    lea r13, [rbx + uxfs_ag_descriptor_t.bitmap]

    ; Atomic Lock-Free Bit-Reset
    lock btr qword [r13 + r12 * 8], rax
    jnc .double_free_err            ; Carry flag 0 means bit was ALREADY 0 (double free!)

    lock inc dword [rbx + uxfs_ag_descriptor_t.free_blocks]

    mov eax, 0
    pop r13
    pop r12
    pop rbx
    ret

.double_free_err:
.invalid_lba:
    mov eax, -22
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_ag_get_stat
; -----------------------------------------------------------------------------
align 32
uxfs_ag_get_stat:
    push rbx
    push rcx

    xor eax, eax
    xor ecx, ecx

.stat_loop:
    cmp ecx, UXFS_AG_MAX_GROUPS
    jge .done_stat

    imul rbx, rcx, uxfs_ag_descriptor_t_size
    lea rbx, [uxfs_ag_table + rbx]

    add eax, [rbx + uxfs_ag_descriptor_t.free_blocks]

    inc ecx
    jmp .stat_loop

.done_stat:
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_ag_update_checksum
; -----------------------------------------------------------------------------
align 32
uxfs_ag_update_checksum:
    push rbx

    mov rbx, rdi
    mov rdi, 0xFFFFFFFF
    lea rsi, [rbx + uxfs_ag_descriptor_t.bitmap]
    mov rdx, UXFS_AG_BITMAP_QWORDS * 8
    call ucmp_crc32_calc
    mov [rbx + uxfs_ag_descriptor_t.checksum], eax

    mov eax, 0
    pop rbx
    ret
