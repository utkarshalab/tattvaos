; Native userspace harness for boot/uefi/transition_tables.asm.

[BITS 64]
default rel

%include "boot/uefi/transition_tables.asm"

TEST_PHYS      equ 0x20000000
TEST_MEMORY    equ 0x00320000
TEST_EXEC      equ 0x00030000
TEST_STUB      equ 0x30056000

%macro LOAD_INPUTS 5
    lea rdi, [rel table_arena]
    mov esi, %1
    mov edx, %2
    mov ecx, %3
    mov r8d, %4
    mov r9d, %5
%endmacro

section .text
global _start
_start:
    LOAD_INPUTS TEST_PHYS, TEST_MEMORY, TEST_EXEC, TEST_STUB, UEFI_TRANSITION_FLAG_NX
    call uefi_transition_build_tables
    jc .fail_1
    lea r10, [rel table_arena]
    cmp rax, r10
    jne .fail_1

    LOAD_INPUTS TEST_PHYS, TEST_MEMORY, TEST_EXEC, TEST_STUB, UEFI_TRANSITION_FLAG_NX
    call uefi_transition_verify_tables
    jc .fail_1

    ; Deterministic pool order: virtual regions 0..2, physical regions
    ; 256..257, then the transition-stub region.
    lea r10, [rel table_arena]
    mov rax, TEST_PHYS | UEFI_PTE_PRESENT
    cmp [r10 + UEFI_TRANSITION_PT_POOL_OFF + 0 * 4096 + 256 * 8], rax
    jne .fail_1
    mov rax, TEST_PHYS + TEST_EXEC - 4096 | UEFI_PTE_PRESENT
    cmp [r10 + UEFI_TRANSITION_PT_POOL_OFF + 0 * 4096 + 303 * 8], rax
    jne .fail_1
    mov rax, TEST_PHYS + TEST_EXEC | UEFI_PTE_PRESENT | UEFI_PTE_RW
    bts rax, 63
    cmp [r10 + UEFI_TRANSITION_PT_POOL_OFF + 0 * 4096 + 304 * 8], rax
    jne .fail_1

    cmp qword [r10 + UEFI_TRANSITION_PT_POOL_OFF + 3 * 4096], 0
    jne .fail_1
    mov rax, TEST_STUB | UEFI_PTE_PRESENT
    cmp [r10 + UEFI_TRANSITION_PT_POOL_OFF + 5 * 4096 + 0x56 * 8], rax
    jne .fail_1
    cmp qword [r10 + UEFI_TRANSITION_PT_POOL_OFF + 6 * 4096], 0
    jne .fail_1

    xor r12d, r12d
    lea r13, [rel table_arena]
.mutation_loop:
    mov r14, r12
    shl r14, 12
    xor qword [r13 + r14], UEFI_PTE_PRESENT
    LOAD_INPUTS TEST_PHYS, TEST_MEMORY, TEST_EXEC, TEST_STUB, UEFI_TRANSITION_FLAG_NX
    call uefi_transition_verify_tables
    jnc .fail_2_restore_first
    xor qword [r13 + r14], UEFI_PTE_PRESENT

    xor qword [r13 + r14 + 4088], UEFI_PTE_PRESENT
    LOAD_INPUTS TEST_PHYS, TEST_MEMORY, TEST_EXEC, TEST_STUB, UEFI_TRANSITION_FLAG_NX
    call uefi_transition_verify_tables
    jnc .fail_2_restore_last
    xor qword [r13 + r14 + 4088], UEFI_PTE_PRESENT

    inc r12
    cmp r12, UEFI_TRANSITION_TABLE_PAGES
    jb .mutation_loop

    LOAD_INPUTS TEST_PHYS, TEST_MEMORY, TEST_EXEC, TEST_STUB, 0
    call uefi_transition_build_tables
    jc .fail_3
    LOAD_INPUTS TEST_PHYS, TEST_MEMORY, TEST_EXEC, TEST_STUB, 0
    call uefi_transition_verify_tables
    jc .fail_3
    lea rdi, [rel table_arena]
    mov ecx, UEFI_TRANSITION_TABLE_BYTES / 8
.no_nx_scan:
    bt qword [rdi], 63
    jc .fail_3
    add rdi, 8
    dec ecx
    jnz .no_nx_scan

    LOAD_INPUTS KERNEL_LOAD, 0x100000, 4096, 0x08000000, UEFI_TRANSITION_FLAG_NX
    call uefi_transition_build_tables
    jc .fail_4
    LOAD_INPUTS KERNEL_LOAD, 0x100000, 4096, 0x08000000, UEFI_TRANSITION_FLAG_NX
    call uefi_transition_verify_tables
    jc .fail_4
    lea r10, [rel table_arena]
    cmp qword [r10 + UEFI_TRANSITION_PT_POOL_OFF + 256 * 8], KERNEL_LOAD | UEFI_PTE_PRESENT
    jne .fail_4

    LOAD_INPUTS 0xFC000000, ULF_MAX_MEMORY_BYTES, ULF_MAX_EXEC_BYTES, 0x08000000, UEFI_TRANSITION_FLAG_NX
    call uefi_transition_build_tables
    jc .fail_5
    LOAD_INPUTS 0xFC000000, ULF_MAX_MEMORY_BYTES, ULF_MAX_EXEC_BYTES, 0x08000000, UEFI_TRANSITION_FLAG_NX
    call uefi_transition_verify_tables
    jc .fail_5

    lea rdi, [rel table_arena]
    mov ecx, UEFI_TRANSITION_TABLE_BYTES / 8
    mov rax, 0xA5A5A5A5A5A5A5A5
    rep stosq

    LOAD_INPUTS TEST_PHYS, 0, TEST_EXEC, TEST_STUB, UEFI_TRANSITION_FLAG_NX
    call uefi_transition_build_tables
    jnc .fail_6
    LOAD_INPUTS TEST_PHYS, 4096, 8192, TEST_STUB, UEFI_TRANSITION_FLAG_NX
    call uefi_transition_build_tables
    jnc .fail_6
    LOAD_INPUTS TEST_PHYS, TEST_MEMORY, TEST_EXEC, KERNEL_LOAD, UEFI_TRANSITION_FLAG_NX
    call uefi_transition_build_tables
    jnc .fail_6
    LOAD_INPUTS TEST_PHYS, TEST_MEMORY, TEST_EXEC, TEST_STUB, 2
    call uefi_transition_build_tables
    jnc .fail_6

    lea rdi, [rel table_arena]
    mov ecx, UEFI_TRANSITION_TABLE_BYTES / 8
    mov rax, 0xA5A5A5A5A5A5A5A5
.poison_scan:
    cmp [rdi], rax
    jne .fail_6
    add rdi, 8
    dec ecx
    jnz .poison_scan

    xor edi, edi
    jmp .exit

.fail_1: mov edi, 1
         jmp .exit
.fail_2_restore_first:
    xor qword [r13 + r14], UEFI_PTE_PRESENT
    jmp .fail_2
.fail_2_restore_last:
    xor qword [r13 + r14 + 4088], UEFI_PTE_PRESENT
.fail_2: mov edi, 2
         jmp .exit
.fail_3: mov edi, 3
         jmp .exit
.fail_4: mov edi, 4
         jmp .exit
.fail_5: mov edi, 5
         jmp .exit
.fail_6: mov edi, 6

.exit:
    mov eax, 60
    syscall

section .bss align=4096
table_arena: resb UEFI_TRANSITION_TABLE_BYTES
