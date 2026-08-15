; =============================================================================
; Tattva OS — lib/ulog/tests/test_ring.asm
; =============================================================================
; Exercises record/ring_push.asm, ring_pop.asm, and ring_wrap.asm's
; overwrite-oldest policy directly, without going through emit_async.asm —
; these are the SPSC primitives everything else in the module trusts.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_TESTS_TEST_RING_ASM
%define LIB_ULOG_TESTS_TEST_RING_ASM

[BITS 64]

%include "lib/ulog/record/record.inc"

section .bss
alignb 8
test_ring_scratch: resb ring_t_size
test_ring_record:  resb LOG_RECORD_SIZE

section .text

; -----------------------------------------------------------------------------
; ulog_test_ring — Output: RAX = 0 pass, -1 fail
; -----------------------------------------------------------------------------
global ulog_test_ring
ulog_test_ring:
    push rbx

    ; zero the scratch ring
    mov rdi, test_ring_scratch
    mov rcx, ring_t_size / 8
    xor rax, rax
    cld
    rep stosq

    ; push one record, pop it back, expect head==tail==1 and pop returns 1
    mov rdi, test_ring_scratch
    mov rsi, test_ring_record
    call log_ring_push

    mov rdi, test_ring_scratch
    mov rsi, test_ring_record
    call log_ring_pop
    test rax, rax
    jz .fail                         ; must have popped something

    mov rax, [test_ring_scratch + ring_t.head]
    cmp rax, 1
    jne .fail
    mov rax, [test_ring_scratch + ring_t.tail]
    cmp rax, 1
    jne .fail

    ; pop again on an empty ring must return 0
    mov rdi, test_ring_scratch
    mov rsi, test_ring_record
    call log_ring_pop
    test rax, rax
    jnz .fail

    ; fill past capacity and confirm .dropped increments (overwrite-oldest)
    mov ebx, ULOG_RING_SLOTS_PER_CPU
    add ebx, 4
.fill_loop:
    test ebx, ebx
    jz .fill_done
    mov rdi, test_ring_scratch
    mov rsi, test_ring_record
    call log_ring_push
    dec ebx
    jmp .fill_loop
.fill_done:
    mov rax, [test_ring_scratch + ring_t.dropped]
    test rax, rax
    jz .fail                         ; must have dropped something on overflow

    xor rax, rax
    jmp .done

.fail:
    mov rax, -1

.done:
    pop rbx
    ret

%endif ; LIB_ULOG_TESTS_TEST_RING_ASM
