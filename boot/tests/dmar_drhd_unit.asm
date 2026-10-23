; Native hostile-input checks for DMAR DRHD and device-scope ownership.
[BITS 64]
default rel

%include "kernel/arch/x86_64/dmar.asm"

TABLE_BYTES       equ 88
DRHD0_OFF         equ DMAR_HEADER_BYTES
DRHD1_OFF         equ DRHD0_OFF + 24
SCOPE0_OFF        equ DRHD0_OFF + 16
OUTPUT_CAPACITY   equ 4

section .text
global _start
_start:
    ; A scoped unit followed by the segment-wide INCLUDE_ALL unit is valid.
    mov r15d, 1
    call reset_fixture
    call parse_default
    jc fail
    cmp eax, 2
    jne fail
    test edx, edx
    jnz fail
    mov eax, 0xFED90000
    cmp qword [rel output + SMP_DMAR_DRHD_BASE_OFF], rax
    jne fail
    cmp dword [rel output + SMP_DMAR_DRHD_TABLE_OFFSET_OFF], DRHD0_OFF
    jne fail
    cmp dword [rel output + SMP_DMAR_DRHD_SCOPE_BYTES_OFF], 8
    jne fail
    cmp dword [rel output + SMP_DMAR_DRHD_SCOPE_COUNT_OFF], 1
    jne fail
    cmp word [rel output + SMP_DMAR_DRHD_SEGMENT_OFF], 0
    jne fail
    cmp byte [rel output + SMP_DMAR_DRHD_FLAGS_OFF], 0
    jne fail
    cmp byte [rel output + SMP_DMAR_DRHD_REG_SIZE_OFF], 2
    jne fail
    mov eax, 0xFED94000
    cmp qword [rel output + SMP_DMAR_DRHD_BYTES + SMP_DMAR_DRHD_BASE_OFF], rax
    jne fail
    cmp byte [rel output + SMP_DMAR_DRHD_BYTES + SMP_DMAR_DRHD_FLAGS_OFF], 1
    jne fail

    ; The declared ACPI extent must fit the caller's accessible mapping.
    mov r15d, 2
    call reset_fixture
    lea rdi, [rel working_table]
    lea rsi, [rel working_table + TABLE_BYTES - 1]
    lea rdx, [rel output]
    mov ecx, OUTPUT_CAPACITY
    call smp_dmar_parse_drhds
    jnc fail
    cmp edx, SMP_DMAR_ERR_SPAN
    jne fail

    ; Zero-length and overrun substructures cannot stall or escape the walk.
    mov r15d, 3
    call reset_fixture
    mov word [rel working_table + DRHD0_OFF + 2], 0
    call fix_checksum
    call parse_default
    jnc fail
    cmp edx, SMP_DMAR_ERR_ENTRY
    jne fail

    mov r15d, 4
    call reset_fixture
    mov word [rel working_table + DRHD0_OFF + 2], TABLE_BYTES
    call fix_checksum
    call parse_default
    jnc fail
    cmp edx, SMP_DMAR_ERR_ENTRY
    jne fail

    ; DRHD flags and the high half of the register-size byte are reserved.
    mov r15d, 5
    call reset_fixture
    mov byte [rel working_table + DRHD0_OFF + 4], 2
    call fix_checksum
    call parse_default
    jnc fail
    cmp edx, SMP_DMAR_ERR_ENTRY
    jne fail

    mov r15d, 6
    call reset_fixture
    mov byte [rel working_table + DRHD0_OFF + 5], 0x10
    call fix_checksum
    call parse_default
    jnc fail
    cmp edx, SMP_DMAR_ERR_ENTRY
    jne fail

    ; A hardware register window must be nonzero, page aligned, and bounded.
    mov r15d, 7
    call reset_fixture
    or qword [rel working_table + DRHD0_OFF + 8], 1
    call fix_checksum
    call parse_default
    jnc fail
    cmp edx, SMP_DMAR_ERR_ENTRY
    jne fail

    mov r15d, 8
    call reset_fixture
    mov qword [rel working_table + DRHD0_OFF + 8], -4096
    call fix_checksum
    call parse_default
    jnc fail
    cmp edx, SMP_DMAR_ERR_ENTRY
    jne fail

    ; Device scopes have an even, bounded length and reserved-zero framing.
    mov r15d, 9
    call reset_fixture
    mov byte [rel working_table + SCOPE0_OFF + 1], 10
    call fix_checksum
    call parse_default
    jnc fail
    cmp edx, SMP_DMAR_ERR_ENTRY
    jne fail

    mov r15d, 10
    call reset_fixture
    mov byte [rel working_table + SCOPE0_OFF + 3], 1
    call fix_checksum
    call parse_default
    jnc fail
    cmp edx, SMP_DMAR_ERR_ENTRY
    jne fail

    mov r15d, 11
    call reset_fixture
    mov byte [rel working_table + SCOPE0_OFF + 6], 32
    call fix_checksum
    call parse_default
    jnc fail
    cmp edx, SMP_DMAR_ERR_ENTRY
    jne fail

    ; Register windows are unique, and INCLUDE_ALL is unique and last per segment.
    mov r15d, 12
    call reset_fixture
    mov rax, [rel working_table + DRHD0_OFF + 8]
    mov [rel working_table + DRHD1_OFF + 8], rax
    call fix_checksum
    call parse_default
    jnc fail
    cmp edx, SMP_DMAR_ERR_DUPLICATE
    jne fail

    mov r15d, 13
    call reset_fixture
    mov byte [rel working_table + DRHD0_OFF + 4], 1
    mov byte [rel working_table + SCOPE0_OFF], 3
    call fix_checksum
    call parse_default
    jnc fail
    cmp edx, SMP_DMAR_ERR_DUPLICATE
    jne fail

    ; Output ownership and capacity are validated before records are trusted.
    mov r15d, 14
    call reset_fixture
    lea rdi, [rel working_table]
    lea rsi, [rel working_table + TABLE_BYTES]
    lea rdx, [rel working_table + DRHD0_OFF]
    mov ecx, 1
    call smp_dmar_parse_drhds
    jnc fail
    cmp edx, SMP_DMAR_ERR_SPAN
    jne fail

    mov r15d, 15
    call reset_fixture
    lea rdi, [rel working_table]
    lea rsi, [rel working_table + TABLE_BYTES]
    lea rdx, [rel output]
    mov ecx, 1
    call smp_dmar_parse_drhds
    jnc fail
    cmp edx, SMP_DMAR_ERR_CAPACITY
    jne fail

    ; A DMAR with no hardware-unit definition cannot back remapping policy.
    mov r15d, 16
    call reset_fixture
    mov word [rel working_table + DRHD0_OFF], 1
    mov word [rel working_table + DRHD1_OFF], 1
    call fix_checksum
    call parse_default
    jnc fail
    cmp edx, SMP_DMAR_ERR_ENTRY
    jne fail

    ; Size=N requires alignment to the complete 2^N-page register window.
    mov r15d, 17
    call reset_fixture
    mov eax, 0xFED91000
    mov [rel working_table + DRHD0_OFF + 8], rax
    call fix_checksum
    call parse_default
    jnc fail
    cmp edx, SMP_DMAR_ERR_ENTRY
    jne fail

    ; Distinct bases still conflict when their complete register windows cross.
    mov r15d, 18
    call reset_fixture
    mov eax, 0xFED92000
    mov [rel working_table + DRHD1_OFF + 8], rax
    call fix_checksum
    call parse_default
    jnc fail
    cmp edx, SMP_DMAR_ERR_DUPLICATE
    jne fail

    ; INCLUDE_ALL still permits an explicitly assigned ACPI namespace device.
    mov r15d, 19
    call reset_fixture
    mov byte [rel working_table + DRHD0_OFF + 4], 1
    mov word [rel working_table + DRHD0_OFF + 6], 1
    mov byte [rel working_table + SCOPE0_OFF], 5
    mov byte [rel working_table + SCOPE0_OFF + 4], 7
    call fix_checksum
    call parse_default
    jc fail
    cmp eax, 2
    jne fail

    ; Top-level remapping structures are monotonically ordered by type.
    mov r15d, 20
    call reset_fixture
    mov word [rel working_table + DRHD0_OFF], 1
    call fix_checksum
    call parse_default
    jnc fail
    cmp edx, SMP_DMAR_ERR_ENTRY
    jne fail

    ; Enumeration ID is reserved for PCI endpoint/subhierarchy scopes.
    mov r15d, 21
    call reset_fixture
    mov byte [rel working_table + SCOPE0_OFF + 4], 1
    call fix_checksum
    call parse_default
    jnc fail
    cmp edx, SMP_DMAR_ERR_ENTRY
    jne fail

    xor edi, edi
    jmp exit
fail:
    mov edi, r15d
exit:
    mov eax, 60
    syscall

parse_default:
    lea rdi, [rel working_table]
    lea rsi, [rel working_table + TABLE_BYTES]
    lea rdx, [rel output]
    mov ecx, OUTPUT_CAPACITY
    jmp smp_dmar_parse_drhds

reset_fixture:
    cld
    lea rsi, [rel dmar_template]
    lea rdi, [rel working_table]
    mov ecx, TABLE_BYTES
    rep movsb
    lea rdi, [rel output]
    xor eax, eax
    mov ecx, OUTPUT_CAPACITY * SMP_DMAR_DRHD_BYTES
    rep stosb
    jmp fix_checksum

fix_checksum:
    mov byte [rel working_table + 9], 0
    lea rsi, [rel working_table]
    mov ecx, TABLE_BYTES
    xor eax, eax
.sum:
    add al, [rsi]
    inc rsi
    dec ecx
    jnz .sum
    neg al
    mov [rel working_table + 9], al
    ret

section .rodata
align 8
dmar_template:
    db "DMAR"
    dd TABLE_BYTES
    db 1, 0
    db "UTOS  "
    db "DRHDTEST"
    dd 1
    db "UTOS"
    dd 1
    db 47
    db DMAR_FLAG_INTR_REMAP
    times 10 db 0

    dw 0, 24                       ; scoped DRHD
    db 0, 2                        ; flags, 16 KiB register-set exponent
    dw 0                           ; PCI segment
    dq 0xFED90000
    db 1, 8, 0, 0, 0, 0, 2, 0     ; endpoint 00:02.0

    dw 0, 16                       ; segment-wide DRHD, deliberately last
    db 1, 0
    dw 0
    dq 0xFED94000

section .bss
alignb 16
working_table: resb TABLE_BYTES
alignb 16
output:        resb OUTPUT_CAPACITY * SMP_DMAR_DRHD_BYTES
