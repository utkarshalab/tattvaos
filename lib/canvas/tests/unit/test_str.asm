; ============================================================================
; String Library Unit Tests
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/test.inc"

extern str_len
extern str_copy
extern str_ncopy
extern str_compare
extern str_ncompare
extern str_find_char
extern str_find_last_char
extern str_starts_with
extern str_ends_with
extern str_to_lower
extern str_to_upper
extern str_dup_arena
extern str_concat_arena
extern arena_init
extern arena_alloc

section .text

global test_str_suite
test_str_suite:
    TEST_SUITE_BEGIN test_str_suite

    ; Test 1: str_len
    TEST_CASE test_str_len
        mov rdi, test_str_hello
        call str_len
        TEST_ASSERT_EQ rax, 5
    TEST_END

    TEST_CASE test_str_len_empty
        mov rdi, test_str_empty
        call str_len
        TEST_ASSERT_EQ rax, 0
    TEST_END

    ; Test 2: str_copy
    TEST_CASE test_str_copy
        sub rsp, 32
        mov rdi, rsp
        mov rsi, test_str_hello
        mov rdx, 32
        call str_copy
        TEST_ASSERT_OK rax
        mov rdi, rsp
        mov rsi, test_str_hello
        call str_compare
        TEST_ASSERT_EQ rax, 0
        add rsp, 32
    TEST_END

    TEST_CASE test_str_copy_truncated
        sub rsp, 8
        mov rdi, rsp
        mov rsi, test_str_hello
        mov rdx, 4
        call str_copy
        TEST_ASSERT_ERROR rax
        add rsp, 8
    TEST_END

    ; Test 3: str_compare
    TEST_CASE test_str_compare_equal
        mov rdi, test_str_hello
        mov rsi, test_str_hello
        call str_compare
        TEST_ASSERT_EQ rax, 0
    TEST_END

    TEST_CASE test_str_compare_diff
        mov rdi, test_str_abc
        mov rsi, test_str_abd
        call str_compare
        TEST_ASSERT_LT rax, 0
    TEST_END

    ; Test 4: str_find_char
    TEST_CASE test_str_find_char
        mov rdi, test_str_hello
        mov rsi, 'e'
        call str_find_char
        TEST_ASSERT_PTR rax
        TEST_ASSERT_EQ rax, test_str_hello + 1
    TEST_END

    TEST_CASE test_str_find_char_not_found
        mov rdi, test_str_hello
        mov rsi, 'z'
        call str_find_char
        TEST_ASSERT_EQ rax, 0
    TEST_END

    ; Test 5: str_starts_with
    TEST_CASE test_str_starts_with
        mov rdi, test_str_hello
        mov rsi, test_str_he
        call str_starts_with
        TEST_ASSERT_EQ rax, 1
    TEST_END

    TEST_CASE test_str_starts_with_false
        mov rdi, test_str_hello
        mov rsi, test_str_el
        call str_starts_with
        TEST_ASSERT_EQ rax, 0
    TEST_END

    ; Test 6: str_ends_with
    TEST_CASE test_str_ends_with
        mov rdi, test_str_hello
        mov rsi, test_str_lo
        call str_ends_with
        TEST_ASSERT_EQ rax, 1
    TEST_END

    ; Test 7: str_to_lower / str_to_upper
    TEST_CASE test_str_to_lower
        sub rsp, 32
        mov rdi, test_str_mixed
        call str_dup_arena
        TEST_ASSERT_PTR rax
        mov rdi, rax
        call str_to_lower
        mov rdi, rax
        mov rsi, test_str_hello
        call str_compare
        TEST_ASSERT_EQ rax, 0
        add rsp, 32
    TEST_END

    TEST_CASE test_str_to_upper
        sub rsp, 32
        mov rdi, test_str_hello
        call str_dup_arena
        TEST_ASSERT_PTR rax
        mov rdi, rax
        call str_to_upper
        mov rdi, rax
        mov rsi, test_str_HELLO
        call str_compare
        TEST_ASSERT_EQ rax, 0
        add rsp, 32
    TEST_END

    ; Test 8: str_concat_arena
    TEST_CASE test_str_concat_arena
        sub rsp, 32
        mov rdi, rsp
        mov rsi, rsp
        add rsi, 32
        mov rdx, 224
        call arena_init
        TEST_ASSERT_OK rax

        mov rdi, rsp
        mov rsi, test_str_hello
        mov rdx, test_str_world
        call str_concat_arena
        TEST_ASSERT_PTR rax
        mov rdi, rax
        mov rsi, test_str_hello_world
        call str_compare
        TEST_ASSERT_EQ rax, 0
        add rsp, 32
    TEST_END

    TEST_SUITE_END

section .rodata

test_str_hello:       db "hello", 0
test_str_empty:       db "", 0
test_str_abc:         db "abc", 0
test_str_abd:         db "abd", 0
test_str_he:          db "he", 0
test_str_el:          db "el", 0
test_str_lo:          db "lo", 0
test_str_mixed:       db "HeLLo", 0
test_str_HELLO:       db "HELLO", 0
test_str_world:       db " world", 0
test_str_hello_world: db "hello world", 0