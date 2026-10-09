; User-mode regression for the traditional page-table spinlock path.
[BITS 64]
default rel

global _start

thread_t.tsx_active equ 0

section .data
align 16
pml4_shuffle_map:
    %assign i 0
    %rep 512
        dw i
        %assign i i + 1
    %endrep

section .text
sched_get_current_thread:
    xor eax, eax                    ; force the non-TSX path
    ret

tsx_begin:
tsx_end:
    ret

%include "lib/mem/virt/paging/pgtable_lock.asm"

section .text
_start:
    lea rbx, [rel pgtable_locks]
    mov byte [rbx + 9], 0x5A
    mov byte [rbx + 10], 0
    mov byte [rbx + 11], 0xA5

    mov rdi, 10
    shl rdi, 39
    call pgtable_lock_acquire

    cmp byte [rbx + 9], 0x5A
    jne .fail
    cmp byte [rbx + 10], 1
    jne .fail
    cmp byte [rbx + 11], 0xA5
    jne .fail

    call pgtable_lock_release
    cmp byte [rbx + 9], 0x5A
    jne .fail
    cmp byte [rbx + 10], 0
    jne .fail
    cmp byte [rbx + 11], 0xA5
    jne .fail

    mov eax, 60
    xor edi, edi
    syscall

.fail:
    mov eax, 60
    mov edi, 1
    syscall
