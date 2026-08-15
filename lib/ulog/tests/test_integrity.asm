; =============================================================================
; Tattva OS — lib/ulog/tests/test_integrity.asm
; =============================================================================
; record_checksum.asm and the record_encode/record_decode round trip —
; corrupt one byte after encoding and confirm decode actually notices.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_TESTS_TEST_INTEGRITY_ASM
%define LIB_ULOG_TESTS_TEST_INTEGRITY_ASM

[BITS 64]

%include "lib/ulog/ulog.inc"

section .bss
alignb 8
test_integrity_record: resb LOG_RECORD_SIZE
test_integrity_scratch: resb LOG_RECORD_SIZE
test_integrity_out:     resb LOG_RECORD_SIZE

section .text

; -----------------------------------------------------------------------------
; ulog_test_integrity — Output: RAX = 0 pass, -1 fail
; -----------------------------------------------------------------------------
global ulog_test_integrity
ulog_test_integrity:
    push rbx

    mov rdi, test_integrity_record
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

    mov byte [test_integrity_record + log_record_t.level], LVL_ERROR
    mov word [test_integrity_record + log_record_t.module_id], MOD_KERNEL_SCHED

    mov rdi, test_integrity_record
    call record_checksum_stamp

    ; a correctly stamped record must decode clean
    mov rdi, test_integrity_record
    mov rsi, test_integrity_out
    call record_decode
    test rax, rax
    jz .fail

    ; corrupt one byte of the payload, leave the checksum alone
    mov byte [test_integrity_record + log_record_t.level], LVL_FATAL

    mov rdi, test_integrity_record
    mov rsi, test_integrity_out
    call record_decode
    test rax, rax
    jnz .fail                        ; must now report a mismatch

    xor rax, rax
    jmp .done

.fail:
    mov rax, -1

.done:
    pop rbx
    ret

%endif ; LIB_ULOG_TESTS_TEST_INTEGRITY_ASM
