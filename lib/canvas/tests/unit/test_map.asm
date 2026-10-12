; ============================================================================
; Hash Map Unit Tests
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/test.inc"

extern map_init
extern map_put
extern map_get
extern map_remove
extern map_count
extern map_clear
extern fnv1a_hash
extern fnv1a_hash_str
extern arena_init
extern arena_alloc

section .text

global test_map_suite
test_map_suite:
    TEST_SUITE_BEGIN test_map_suite

    TEST_CASE test_map_init
        sub rsp, 256
        mov rdi, rsp
        mov rsi, rsp
        add rsi, 40
        mov rdx, 16
        call map_init
        TEST_ASSERT_OK rax
        mov rdi, rsp
        call map_count
        TEST_ASSERT_EQ rax, 0
    TEST_END

    TEST_CASE test_map_put_get
        sub rsp, 256
        mov rdi, rsp
        mov rsi, rsp
        add rsi, 40
        mov rdx, 16
        call map_init
        TEST_ASSERT_OK rax

        mov rdi, rsp
        mov rsi, test_key1
        mov rdx, 3
        mov rcx, test_val1
        call map_put
        TEST_ASSERT_OK rax

        mov rdi, rsp
        mov rsi, test_key1
        mov rdx, 3
        call map_get
        TEST_ASSERT_PTR rax
        TEST_ASSERT_EQ rax, test_val1
    TEST_END

    TEST_CASE test_map_update
        sub rsp, 256
        mov rdi, rsp
        mov rsi, rsp
        add rsi, 40
        mov rdx, 16
        call map_init
        TEST_ASSERT_OK rax

        mov rdi, rsp
        mov rsi, test_key1
        mov rdx, 3
        mov rcx, test_val1
        call map_put
        TEST_ASSERT_OK rax

        mov rdi, rsp
        mov rsi, test_key1
        mov rdx, 3
        mov rcx, test_val2
        call map_put
        TEST_ASSERT_OK rax

        mov rdi, rsp
        mov rsi, test_key1
        mov rdx, 3
        call map_get
        TEST_ASSERT_EQ rax, test_val2
    TEST_END

    TEST_CASE test_map_remove
        sub rsp, 256
        mov rdi, rsp
        mov rsi, rsp
        add rsi, 40
        mov rdx, 16
        call map_init
        TEST_ASSERT_OK rax

        mov rdi, rsp
        mov rsi, test_key1
        mov rdx, 3
        mov rcx, test_val1
        call map_put
        TEST_ASSERT_OK rax

        mov rdi, rsp
        mov rsi, test_key1
        mov rdx, 3
        call map_remove
        TEST_ASSERT_OK rax

        mov rdi, rsp
        mov rsi, test_key1
        mov rdx, 3
        call map_get
        TEST_ASSERT_EQ rax, 0
    TEST_END

    TEST_CASE test_map_fnv1a
        mov rdi, test_key1
        mov rsi, 3
        call fnv1a_hash
        TEST_ASSERT_PTR rax

        mov rdi, test_key1
        call fnv1a_hash_str
        TEST_ASSERT_PTR rax
    TEST_END

    TEST_CASE test_map_clear
        sub rsp, 256
        mov rdi, rsp
        mov rsi, rsp
        add rsi, 40
        mov rdx, 16
        call map_init
        TEST_ASSERT_OK rax

        mov rdi, rsp
        mov rsi, test_key1
        mov rdx, 3
        mov rcx, test_val1
        call map_put
        TEST_ASSERT_OK rax

        mov rdi, rsp
        call map_clear
        TEST_ASSERT_OK rax

        mov rdi, rsp
        call map_count
        TEST_ASSERT_EQ rax, 0
    TEST_END

    TEST_SUITE_END

section .data
test_key1: db "foo", 0
test_key2: db "bar", 0
test_val1: dq 0x1111111111111111
test_val2: dq 0x2222222222222222