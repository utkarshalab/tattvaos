; Native hostile-input checks for kernel/arch/x86_64/dmar.asm.
[BITS 64]
default rel

%include "kernel/arch/x86_64/dmar.asm"

section .text
global _start
_start:
    mov byte [rel dmar_table + 37], DMAR_FLAG_INTR_REMAP
    call fix_checksum
    call parse
    jc fail_valid
    cmp eax, DMAR_FLAG_INTR_REMAP
    jne fail_valid

    mov byte [rel dmar_table + 37], DMAR_FLAG_INTR_REMAP | DMAR_FLAG_X2APIC_OPT_OUT
    call fix_checksum
    call parse
    jc fail_opt_out
    cmp eax, DMAR_FLAG_INTR_REMAP | DMAR_FLAG_X2APIC_OPT_OUT
    jne fail_opt_out

    mov byte [rel dmar_table + 37], DMAR_FLAG_X2APIC_OPT_OUT
    call fix_checksum
    call parse
    jnc fail_dependent_flag

    mov byte [rel dmar_table + 37], 1 << 3
    call fix_checksum
    call parse
    jnc fail_reserved_flag

    mov byte [rel dmar_table + 37], 0
    mov byte [rel dmar_table + 38], 1
    call fix_checksum
    call parse
    jnc fail_reserved_byte
    mov byte [rel dmar_table + 38], 0

    call fix_checksum
    inc byte [rel dmar_table + 9]
    call parse
    jnc fail_checksum

    call fix_checksum
    lea rdi, [rel dmar_table]
    lea rsi, [rel dmar_table + DMAR_HEADER_BYTES - 1]
    call smp_dmar_policy_parse
    jnc fail_bounds

    xor edi, edi
    jmp exit
fail_valid:
    mov edi, 1
    jmp exit
fail_opt_out:
    mov edi, 2
    jmp exit
fail_dependent_flag:
    mov edi, 3
    jmp exit
fail_reserved_flag:
    mov edi, 4
    jmp exit
fail_reserved_byte:
    mov edi, 5
    jmp exit
fail_checksum:
    mov edi, 6
    jmp exit
fail_bounds:
    mov edi, 7
exit:
    mov eax, 60
    syscall

parse:
    lea rdi, [rel dmar_table]
    lea rsi, [rel dmar_table + DMAR_HEADER_BYTES]
    jmp smp_dmar_policy_parse

fix_checksum:
    mov byte [rel dmar_table + 9], 0
    lea rsi, [rel dmar_table]
    mov ecx, DMAR_HEADER_BYTES
    xor eax, eax
.sum:
    add al, [rsi]
    inc rsi
    dec ecx
    jnz .sum
    neg al
    mov [rel dmar_table + 9], al
    ret

section .data
align 8
dmar_table:
    db "DMAR"
    dd DMAR_HEADER_BYTES
    db 1, 0
    db "UTOS  "
    db "DMARTEST"
    dd 1
    db "UTOS"
    dd 1
    db 47
    db 0
    times 10 db 0
