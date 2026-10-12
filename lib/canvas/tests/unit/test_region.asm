; ============================================================================
; Region Unit Tests
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/test.inc"

extern region_init
extern region_add_rect
extern region_clear
extern region_is_empty
extern arena_init
extern arena_alloc

section .text

global test_region_suite
test_region_suite:
    TEST_SUITE_BEGIN test_region_suite

    TEST_CASE test_region_init
        sub rsp, 256
        mov rdi, rsp
        mov rsi, rsp
        add rsi, 24
        mov rdx, 8
        call region_init
        TEST_ASSERT_OK rax
        mov rdi, rsp
        call region_is_empty
        TEST_ASSERT_EQ rax, 1
    TEST_END

    TEST_CASE test_region_add_rect
        sub rsp, 256
        mov rdi, rsp
        mov rsi, rsp
        add rsi, 24
        mov rdx, 8
        call region_init
        TEST_ASSERT_OK rax

        mov rdi, rsp
        mov rsi, 10
        mov rdx, 20
        mov rcx, 30
        mov r8, 40
        call region_add_rect
        TEST_ASSERT_OK rax

        mov rdi, rsp
        call region_is_empty
        TEST_ASSERT_EQ rax, 0
    TEST_END

    TEST_CASE test_region_clear
        sub rsp, 256
        mov rdi, rsp
        mov rsi, rsp
        add rsi, 24
        mov rdx, 8
        call region_init
        TEST_ASSERT_OK rax

        mov rdi, rsp
        mov rsi, 10
        mov rdx, 20
        mov rcx, 30
        mov r8, 40
        call region_add_rect
        TEST_ASSERT_OK rax

        mov rdi, rsp
        call region_clear
        TEST_ASSERT_OK rax

        mov rdi, rsp
        call region_is_empty
        TEST_ASSERT_EQ rax, 1
    TEST_END

    TEST_SUITE_END