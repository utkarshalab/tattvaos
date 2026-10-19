; ============================================================================
; Test Framework Macros — Unit Tests on Tattva
; Reports results over serial, no external dependencies
; ============================================================================

%ifndef __TEST_INC__
%define __TEST_INC__

%include "inc/macros.inc"
%include "inc/tattva.inc"

; ---------------------------------------------------------------------------
; Test Statistics (in .bss)
; ---------------------------------------------------------------------------

section .bss
test_passed:    resq 1
test_failed:    resq 1
test_total:     resq 1
current_test:   resq 1

; ---------------------------------------------------------------------------
; Test Lifecycle Macros
; ---------------------------------------------------------------------------

%macro TEST_SUITE_BEGIN 1
    section .text
    global %1
    %1:
        PROLOGUE_SAVE rbx, r12, r13, r14, r15
        ; Initialize counters
        xor rax, rax
        mov [test_passed], rax
        mov [test_failed], rax
        mov [test_total], rax
        ; Print suite header
        mov rdi, suite_fmt
        mov rsi, %1
        call tv_log_printf
%endmacro

%macro TEST_SUITE_END 0
    ; Print summary
    mov rdi, summary_fmt
    mov rsi, [test_total]
    mov rdx, [test_passed]
    mov rcx, [test_failed]
    call tv_log_printf
    ; Return exit code: 0 if all passed, 1 if any failed
    mov rax, [test_failed]
    test rax, rax
    jz .all_passed
    mov rax, 1
    ret
.all_passed:
    xor rax, rax
    ret
%endmacro

%macro TEST_CASE 1
    push rdi
    lea rdi, [rel %1]
    mov [current_test], rdi
    call test_case_begin
    pop rdi
%endmacro

%macro TEST_ASSERT 1
    ; %1 = condition (register or memory)
    test %1, %1
    jnz %%pass
    call test_assert_fail
    jmp %%done
%%pass:
    call test_assert_pass
%%done:
%endmacro

%macro TEST_ASSERT_EQ 2
    cmp %1, %2
    je %%pass
    call test_assert_eq_fail
    jmp %%done
%%pass:
    call test_assert_pass
%%done:
%endmacro

%macro TEST_ASSERT_NE 2
    cmp %1, %2
    jne %%pass
    call test_assert_ne_fail
    jmp %%done
%%pass:
    call test_assert_pass
%%done:
%endmacro

%macro TEST_ASSERT_PTR 1
    test %1, %1
    jnz %%pass
    call test_assert_null_fail
    jmp %%done
%%pass:
    call test_assert_pass
%%done:
%endmacro

%macro TEST_ASSERT_ERROR 1
    ; %1 = register with return value, expect negative
    test %1, %1
    js %%pass
    call test_assert_error_fail
    jmp %%done
%%pass:
    call test_assert_pass
%%done:
%endmacro

%macro TEST_ASSERT_OK 1
    test %1, %1
    jns %%pass
    call test_assert_ok_fail
    jmp %%done
%%pass:
    call test_assert_pass
%%done:
%endmacro

%macro TEST_ASSERT_ALIGNED 2
    ; %1 = value to check, %2 = alignment (power of 2)
    mov rax, %1
    mov rcx, %2
    dec rcx
    test rax, rcx
    jz %%pass
    call test_assert_fail
    jmp %%done
%%pass:
    call test_assert_pass
%%done:
%endmacro

%macro TEST_ASSERT_GE 2
    cmp %1, %2
    jge %%pass
    call test_assert_fail
    jmp %%done
%%pass:
    call test_assert_pass
%%done:
%endmacro

%macro TEST_ASSERT_LE 2
    cmp %1, %2
    jle %%pass
    call test_assert_fail
    jmp %%done
%%pass:
    call test_assert_pass
%%done:
%endmacro

%macro TEST_ASSERT_LT 2
    cmp %1, %2
    jl %%pass
    call test_assert_fail
    jmp %%done
%%pass:
    call test_assert_pass
%%done:
%endmacro

%macro TEST_ASSERT_NE 2
    cmp %1, %2
    jne %%pass
    call test_assert_ne_fail
    jmp %%done
%%pass:
    call test_assert_pass
%%done:
%endmacro

%macro TEST_ASSERT_PTR 1
    test %1, %1
    jnz %%pass
    call test_assert_null_fail
    jmp %%done
%%pass:
    call test_assert_pass
%%done:
%endmacro

%macro TEST_ASSERT_ERROR 1
    ; %1 = register with return value, expect negative
    test %1, %1
    js %%pass
    call test_assert_error_fail
    jmp %%done
%%pass:
    call test_assert_pass
%%done:
%endmacro

%macro TEST_ASSERT_OK 1
    test %1, %1
    jns %%pass
    call test_assert_ok_fail
    jmp %%done
%%pass:
    call test_assert_pass
%%done:
%endmacro

%macro TEST_END 0
    call test_case_end
%endmacro

; ---------------------------------------------------------------------------
; Test Helper Functions
; ---------------------------------------------------------------------------

section .text

test_case_begin:
    PROLOGUE_SAVE rbx
    mov rbx, [current_test]
    inc qword [test_total]
    mov rdi, test_begin_fmt
    mov rsi, rbx
    call tv_log_printf
    EPILOGUE_RESTORE rbx
    ret

test_case_end:
    PROLOGUE
    mov rdi, test_end_fmt
    call tv_log_printf
    ret

test_assert_pass:
    PROLOGUE
    inc qword [test_passed]
    mov rdi, assert_pass_fmt
    mov rsi, [current_test]
    call tv_log_printf
    ret

test_assert_fail:
    PROLOGUE
    inc qword [test_failed]
    mov rdi, assert_fail_fmt
    mov rsi, [current_test]
    call tv_log_printf
    ret

test_assert_eq_fail:
    PROLOGUE_SAVE rbx
    inc qword [test_failed]
    mov rbx, [current_test]
    mov rdi, assert_eq_fail_fmt
    mov rsi, rbx
    ; Expected in rsi, actual in rdx (set by caller convention)
    call tv_log_printf
    EPILOGUE_RESTORE rbx
    ret

test_assert_ne_fail:
    PROLOGUE_SAVE rbx
    inc qword [test_failed]
    mov rbx, [current_test]
    mov rdi, assert_ne_fail_fmt
    mov rsi, rbx
    call tv_log_printf
    EPILOGUE_RESTORE rbx
    ret

test_assert_null_fail:
    PROLOGUE_SAVE rbx
    inc qword [test_failed]
    mov rbx, [current_test]
    mov rdi, assert_null_fail_fmt
    mov rsi, rbx
    call tv_log_printf
    EPILOGUE_RESTORE rbx
    ret

test_assert_error_fail:
    PROLOGUE_SAVE rbx
    inc qword [test_failed]
    mov rbx, [current_test]
    mov rdi, assert_error_fail_fmt
    mov rsi, rbx
    call tv_log_printf
    EPILOGUE_RESTORE rbx
    ret

test_assert_ok_fail:
    PROLOGUE_SAVE rbx
    inc qword [test_failed]
    mov rbx, [current_test]
    mov rdi, assert_ok_fail_fmt
    mov rsi, rbx
    call tv_log_printf
    EPILOGUE_RESTORE rbx
    ret

section .rodata

suite_fmt:            db "=== TEST SUITE: %s ===", 10, 0
summary_fmt:          db "=== SUMMARY: total=%d passed=%d failed=%d ===", 10, 0
test_begin_fmt:       db "  TEST: %s", 10, 0
test_end_fmt:         db "  DONE", 10, 0
assert_pass_fmt:      db "    PASS: %s", 10, 0
assert_fail_fmt:      db "    FAIL: %s", 10, 0
assert_eq_fail_fmt:   db "    FAIL: %s (expected=%p actual=%p)", 10, 0
assert_ne_fail_fmt:   db "    FAIL: %s (values equal)", 10, 0
assert_null_fail_fmt: db "    FAIL: %s (null pointer)", 10, 0
assert_error_fail_fmt: db "    FAIL: %s (expected error)", 10, 0
assert_ok_fail_fmt:   db "    FAIL: %s (expected success)", 10, 0

%endif ; __TEST_INC__