%ifndef GUARD_STORAGE_UXFS_CACHE_TMPFS_ASM
%define GUARD_STORAGE_UXFS_CACHE_TMPFS_ASM
; =============================================================================
; Tattva OS — storage/uxfs/cache/tmpfs.asm
; =============================================================================
; In-Memory Temporary RAM Filesystem (tmpfs) Engine for UXFS.
;
; Implements zero-latency in-memory files and directory structures in RAM.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "storage/uxfs/uxfs.inc"

%define TMPFS_MAX_FILES               256

struc tmpfs_file_entry_t
    .name:               resb 64     ; Filename label
    .size_bytes:         resq 1      ; Length in bytes
    .ram_buffer_ptr:     resq 1      ; Pointer to dynamic RAM buffer
endstruc

section .data
align 16
global tmpfs_file_table
tmpfs_file_table: times TMPFS_MAX_FILES * tmpfs_file_entry_t_size db 0
tmpfs_file_count: dq 0

section .text

global uxfs_tmpfs_init
global uxfs_tmpfs_create_file
global uxfs_tmpfs_read_file

; -----------------------------------------------------------------------------
; uxfs_tmpfs_init
; -----------------------------------------------------------------------------
align 32
uxfs_tmpfs_init:
    push rdi
    push rcx
    push rax

    lea rdi, [tmpfs_file_table]
    mov rcx, TMPFS_MAX_FILES * tmpfs_file_entry_t_size
    xor al, al
    rep stosb

    mov qword [tmpfs_file_count], 0

    pop rax
    pop rcx
    pop rdi
    ret

; -----------------------------------------------------------------------------
; uxfs_tmpfs_create_file
;
; Creates an in-memory RAM file in tmpfs table.
;
; Inputs:
;   RDI = Pointer to filename string
;   RSI = Pointer to RAM data buffer
;   RDX = File length in bytes
; -----------------------------------------------------------------------------
align 32
uxfs_tmpfs_create_file:
    push rbx
    push r12
    push r13
    push r14

    mov r12, rdi
    mov r13, rsi
    mov r14, rdx

    mov rax, [tmpfs_file_count]
    cmp rax, TMPFS_MAX_FILES
    jge .tmpfs_full

    imul rbx, rax, tmpfs_file_entry_t_size
    lea rbx, [tmpfs_file_table + rbx]

    inc qword [tmpfs_file_count]

    mov [rbx + tmpfs_file_entry_t.ram_buffer_ptr], r13
    mov [rbx + tmpfs_file_entry_t.size_bytes], r14

    mov eax, 0
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.tmpfs_full:
    mov eax, -1
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_tmpfs_read_file
; -----------------------------------------------------------------------------
align 32
uxfs_tmpfs_read_file:
    push rbx
    push r12
    push r13

    mov r12, rdi
    mov r13, rsi

    xor ecx, ecx
.scan_tmpfs_loop:
    cmp ecx, [tmpfs_file_count]
    jge .tmpfs_not_found

    imul rbx, rcx, tmpfs_file_entry_t_size
    lea rbx, [tmpfs_file_table + rbx]

    mov rax, [rbx + tmpfs_file_entry_t.ram_buffer_ptr]
    test rax, rax
    jnz .found_tmpfs_file

    inc ecx
    jmp .scan_tmpfs_loop

.found_tmpfs_file:
    pop r13
    pop r12
    pop rbx
    ret

.tmpfs_not_found:
    xor rax, rax
    pop r13
    pop r12
    pop rbx
    ret

%endif ; GUARD_STORAGE_UXFS_CACHE_TMPFS_ASM
