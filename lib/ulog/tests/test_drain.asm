; =============================================================================
; Tattva OS — lib/ulog/tests/test_drain.asm
; =============================================================================
; batch.asm's collection loop against a scratch ring, and
; backpressure_drop_oldest.asm's shift-and-free behavior once the pool runs
; out mid-collection.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_TESTS_TEST_DRAIN_ASM
%define LIB_ULOG_TESTS_TEST_DRAIN_ASM

[BITS 64]

%include "lib/ulog/record/record.inc"

section .bss
alignb 8
test_drain_ring:   resb ring_t_size
test_drain_record: resb LOG_RECORD_SIZE

section .text

; -----------------------------------------------------------------------------
; ulog_test_drain — Output: RAX = 0 pass, -1 fail
; -----------------------------------------------------------------------------
global ulog_test_drain
ulog_test_drain:
    push rbx
    push r12

    call record_pool_init
    test rax, rax
    jz .fail

    mov rdi, test_drain_ring
    mov rcx, ring_t_size / 8
    xor rax, rax
    cld
    rep stosq

    call batch_reset

    ; push 5 records into the scratch ring
    mov r12, 5
.push_loop:
    test r12, r12
    jz .push_done
    mov rdi, test_drain_ring
    mov rsi, test_drain_record
    call log_ring_push
    dec r12
    jmp .push_loop
.push_done:

    mov rdi, test_drain_ring
    call batch_collect_from_ring
    cmp rax, 5
    jne .fail

    mov eax, [ulog_batch_count]
    cmp eax, 5
    jne .fail

    ; drop-oldest must free exactly one batch slot and shrink the count by one
    call backpressure_apply_drop_oldest
    test rax, rax
    jz .fail
    mov eax, [ulog_batch_count]
    cmp eax, 4
    jne .fail

    xor rax, rax
    jmp .done

.fail:
    mov rax, -1

.done:
    pop r12
    pop rbx
    ret

%endif ; LIB_ULOG_TESTS_TEST_DRAIN_ASM
