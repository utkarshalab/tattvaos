; =============================================================================
; Tattva OS — lib/ulog/tests/test_format.asm
; =============================================================================
; json_render_line's shape: starts with `{`, ends with `}\n`, and reports a
; length that actually matches what it wrote — the exact class of bug
; format/json_render.asm's length calculation had before this test existed.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_TESTS_TEST_FORMAT_ASM
%define LIB_ULOG_TESTS_TEST_FORMAT_ASM

[BITS 64]

%include "lib/ulog/ulog.inc"

section .bss
alignb 8
test_format_record: resb LOG_RECORD_SIZE
test_format_buf:     resb 256

section .text

; -----------------------------------------------------------------------------
; ulog_test_format — Output: RAX = 0 pass, -1 fail
; -----------------------------------------------------------------------------
global ulog_test_format
ulog_test_format:
    push rbx

    mov rdi, test_format_record
    mov rcx, LOG_RECORD_SIZE / 8
    xor rax, rax
.zero_loop:
    test rcx, rcx
    jz .zero_done
    mov [rdi], rax
    add rdi, 8
    dec rcx
    jmp .zero_loop
.zero_done:

    mov byte [test_format_record + log_record_t.level], LVL_INFO
    mov word [test_format_record + log_record_t.module_id], MOD_KERNEL_SCHED
    mov qword [test_format_record + log_record_t.msg_ptr], .msg

    mov rdi, test_format_record
    mov rsi, test_format_buf
    mov rdx, 256
    call json_render_line
    test rax, rax
    jz .fail
    mov rbx, rax

    cmp byte [test_format_buf], '{'
    jne .fail

    lea rax, [test_format_buf + rbx - 1]
    cmp byte [rax], 10               ; must end with '\n'
    jne .fail

    xor rax, rax
    jmp .done

.fail:
    mov rax, -1

.done:
    pop rbx
    ret

section .rodata
.msg: db "format test message", 0

%endif ; LIB_ULOG_TESTS_TEST_FORMAT_ASM
