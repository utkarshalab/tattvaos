; ============================================================================
; Handle Table Unit Tests
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/test.inc"

extern handle_table_init
extern handle_create
extern handle_resolve
extern handle_destroy
extern handle_count
extern handle_table_clear
extern arena_init
extern arena_alloc

section .text

global test_handle_suite
test_handle_suite:
    TEST_SUITE_BEGIN test_handle_suite

    ; Test 1: Basic create/resolve/destroy
    TEST_CASE test_handle_basic
        sub rsp, 256
        mov rdi, rsp
        mov rsi, rsp
        add rsi, 48
        mov rdx, 16
        call handle_table_init
        TEST_ASSERT_OK rax

        ; Create handle
        mov rdi, rsp
        mov rsi, test_obj1
        call handle_create
        TEST_ASSERT_PTR rax
        mov rbx, rax

        ; Resolve
        mov rdi, rsp
        mov rsi, rbx
        call handle_resolve
        TEST_ASSERT_PTR rax
        TEST_ASSERT_EQ rax, test_obj1

        ; Destroy
        mov rdi, rsp
        mov rsi, rbx
        call handle_destroy
        TEST_ASSERT_OK rax

        ; Resolve fails
        mov rdi, rsp
        mov rsi, rbx
        call handle_resolve
        TEST_ASSERT_EQ rax, 0
    TEST_END

    ; Test 2: Multiple handles
    TEST_CASE test_handle_multiple
        sub rsp, 256
        mov rdi, rsp
        mov rsi, rsp
        add rsi, 48
        mov rdx, 32
        call handle_table_init
        TEST_ASSERT_OK rax

        mov rdi, rsp
        mov rsi, test_obj1
        call handle_create
        TEST_ASSERT_PTR rax
        mov r12, rax

        mov rdi, rsp
        mov rsi, test_obj2
        call handle_create
        TEST_ASSERT_PTR rax
        mov r13, rax

        mov rdi, rsp
        mov rsi, test_obj3
        call handle_create
        TEST_ASSERT_PTR rax
        mov r14, rax

        ; Resolve all
        mov rdi, rsp
        mov rsi, r12
        call handle_resolve
        TEST_ASSERT_EQ rax, test_obj1

        mov rdi, rsp
        mov rsi, r13
        call handle_resolve
        TEST_ASSERT_EQ rax, test_obj2

        mov rdi, rsp
        mov rsi, r14
        call handle_resolve
        TEST_ASSERT_EQ rax, test_obj3

        ; Count
        mov rdi, rsp
        call handle_count
        TEST_ASSERT_EQ rax, 3

        ; Destroy middle
        mov rdi, rsp
        mov rsi, r13
        call handle_destroy
        TEST_ASSERT_OK rax

        mov rdi, rsp
        call handle_count
        TEST_ASSERT_EQ rax, 2
    TEST_END

    ; Test 3: Generation wraparound
    TEST_CASE test_handle_generation
        sub rsp, 256
        mov rdi, rsp
        mov rsi, rsp
        add rsi, 48
        mov rdx, 16
        call handle_table_init
        TEST_ASSERT_OK rax

        ; Create/destroy same slot 4096 times
        mov rcx, 4096
.wrap_loop:
        mov rdi, rsp
        mov rsi, test_obj1
        call handle_create
        TEST_ASSERT_PTR rax
        mov r12, rax

        mov rdi, rsp
        mov rsi, r12
        call handle_destroy
        TEST_ASSERT_OK rax

        dec rcx
        jnz .wrap_loop

        ; Next create should have new generation
        mov rdi, rsp
        mov rsi, test_obj1
        call handle_create
        TEST_ASSERT_PTR rax

        mov rdi, rsp
        mov rsi, rax
        call handle_resolve
        TEST_ASSERT_EQ rax, test_obj1
    TEST_END

    ; Test 4: Invalid handle
    TEST_CASE test_handle_invalid
        sub rsp, 256
        mov rdi, rsp
        mov rsi, rsp
        add rsi, 48
        mov rdx, 16
        call handle_table_init
        TEST_ASSERT_OK rax

        ; Random invalid handle
        mov rdi, rsp
        mov rsi, 0xDEADBEEF
        call handle_resolve
        TEST_ASSERT_EQ rax, 0

        ; Destroy invalid
        mov rdi, rsp
        mov rsi, 0xDEADBEEF
        call handle_destroy
        TEST_ASSERT_ERROR rax
    TEST_END

    ; Test 5: Clear
    TEST_CASE test_handle_clear
        sub rsp, 256
        mov rdi, rsp
        mov rsi, rsp
        add rsi, 48
        mov rdx, 16
        call handle_table_init
        TEST_ASSERT_OK rax

        mov rdi, rsp
        mov rsi, test_obj1
        call handle_create
        TEST_ASSERT_PTR rax
        mov rdi, rsp
        mov rsi, test_obj2
        call handle_create
        TEST_ASSERT_PTR rax

        mov rdi, rsp
        call handle_clear
        TEST_ASSERT_OK rax

        mov rdi, rsp
        call handle_count
        TEST_ASSERT_EQ rax, 0
    TEST_END

    TEST_SUITE_END

section .data
test_obj1: dq 0x1111111111111111
test_obj2: dq 0x2222222222222222
test_obj3: dq 0x3333333333333333