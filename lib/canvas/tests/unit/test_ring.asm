; ============================================================================
; Ring Buffer Unit Tests
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/test.inc"

extern ring_init
extern ring_push
extern ring_pop
extern ring_peek
extern ring_available
extern ring_free
extern ring_clear
extern arena_init
extern arena_alloc

section .text

global test_ring_suite
test_ring_suite:
    TEST_SUITE_BEGIN test_ring_suite

    ; Test 1: Basic init and push/pop
    TEST_CASE test_ring_basic
        sub rsp, 256
        mov rdi, rsp
        mov rsi, rsp
        add rsi, 32
        mov rdx, 8      ; capacity
        mov rcx, 4      ; element size
        call ring_init
        TEST_ASSERT_OK rax

        ; Push element
        mov rdi, rsp
        mov rsi, test_elem1
        call ring_push
        TEST_ASSERT_OK rax

        ; Pop element
        sub rsp, 16
        mov rdi, rsp
        mov rsi, rsp
        add rsi, 8
        call ring_pop
        TEST_ASSERT_OK rax
        TEST_ASSERT_EQ qword [rsp], 0x1122334455667788
        add rsp, 16

        ; Ring empty
        mov rdi, rsp
        call ring_available
        TEST_ASSERT_EQ rax, 0
    TEST_END

    ; Test 2: Multiple elements
    TEST_CASE test_ring_multiple
        sub rsp, 256
        mov rdi, rsp
        mov rsi, rsp
        add rsi, 32
        mov rdx, 8
        mov rcx, 4
        call ring_init
        TEST_ASSERT_OK rax

        mov rdi, rsp
        mov rsi, test_elem1
        call ring_push
        TEST_ASSERT_OK rax
        mov rdi, rsp
        mov rsi, test_elem2
        call ring_push
        TEST_ASSERT_OK rax
        mov rdi, rsp
        mov rsi, test_elem3
        call ring_push
        TEST_ASSERT_OK rax

        mov rdi, rsp
        call ring_available
        TEST_ASSERT_EQ rax, 3

        ; Pop all
        sub rsp, 16
        mov rdi, rsp
        mov rsi, rsp
        add rsi, 8
        call ring_pop
        TEST_ASSERT_OK rax
        TEST_ASSERT_EQ qword [rsp], 0x1122334455667788

        call ring_pop
        TEST_ASSERT_OK rax
        TEST_ASSERT_EQ qword [rsp], 0xAABBCCDDEEFF0011

        call ring_pop
        TEST_ASSERT_OK rax
        TEST_ASSERT_EQ qword [rsp], 0x123456789ABCDEF0

        ; Empty
        call ring_available
        TEST_ASSERT_EQ rax, 0
        add rsp, 16
    TEST_END

    ; Test 3: Wraparound
    TEST_CASE test_ring_wraparound
        sub rsp, 256
        mov rdi, rsp
        mov rsi, rsp
        add rsi, 32
        mov rdx, 4
        mov rcx, 8
        call ring_init
        TEST_ASSERT_OK rax

        ; Fill
        mov rdi, rsp
        mov rsi, test_elem1
        call ring_push
        TEST_ASSERT_OK rax
        mov rdi, rsp
        mov rsi, test_elem2
        call ring_push
        TEST_ASSERT_OK rax
        mov rdi, rsp
        mov rsi, test_elem3
        call ring_push
        TEST_ASSERT_OK rax
        mov rdi, rsp
        mov rsi, test_elem4
        call ring_push
        TEST_ASSERT_OK rax

        ; Full
        mov rdi, rsp
        call ring_free
        TEST_ASSERT_EQ rax, 0

        ; Pop two
        sub rsp, 16
        mov rdi, rsp
        mov rsi, rsp
        add rsi, 8
        call ring_pop
        TEST_ASSERT_OK rax
        call ring_pop
        TEST_ASSERT_OK rax

        ; Push two more (wraparound)
        mov rdi, rsp
        mov rsi, test_elem5
        call ring_push
        TEST_ASSERT_OK rax
        mov rdi, rsp
        mov rsi, test_elem6
        call ring_push
        TEST_ASSERT_OK rax

        ; Verify order
        call ring_pop
        TEST_ASSERT_OK rax
        TEST_ASSERT_EQ qword [rsp], 0x123456789ABCDEF0
        call ring_pop
        TEST_ASSERT_OK rax
        TEST_ASSERT_EQ qword [rsp], 0xAABBCCDDEEFF0011
        call ring_pop
        TEST_ASSERT_OK rax
        TEST_ASSERT_EQ qword [rsp], 0x1122334455667788
        call ring_pop
        TEST_ASSERT_OK rax
        TEST_ASSERT_EQ qword [rsp], 0xFEDCBA9876543210
        add rsp, 16
    TEST_END

    ; Test 4: Peek
    TEST_CASE test_ring_peek
        sub rsp, 256
        mov rdi, rsp
        mov rsi, rsp
        add rsi, 32
        mov rdx, 8
        mov rcx, 8
        call ring_init
        TEST_ASSERT_OK rax

        mov rdi, rsp
        mov rsi, test_elem1
        call ring_push
        TEST_ASSERT_OK rax

        sub rsp, 16
        mov rdi, rsp
        mov rsi, rsp
        add rsi, 8
        call ring_peek
        TEST_ASSERT_OK rax
        TEST_ASSERT_EQ qword [rsp], 0x1122334455667788

        ; Still available
        mov rdi, rsp
        add rdi, 16
        call ring_available
        TEST_ASSERT_EQ rax, 1
        add rsp, 16
    TEST_END

    ; Test 5: Clear
    TEST_CASE test_ring_clear
        sub rsp, 256
        mov rdi, rsp
        mov rsi, rsp
        add rsi, 32
        mov rdx, 8
        mov rcx, 8
        call ring_init
        TEST_ASSERT_OK rax

        mov rdi, rsp
        mov rsi, test_elem1
        call ring_push
        TEST_ASSERT_OK rax

        mov rdi, rsp
        call ring_clear
        TEST_ASSERT_OK rax

        mov rdi, rsp
        call ring_available
        TEST_ASSERT_EQ rax, 0
    TEST_END

    ; Test 6: Full/Empty errors
    TEST_CASE test_ring_full
        sub rsp, 256
        mov rdi, rsp
        mov rsi, rsp
        add rsi, 32
        mov rdx, 2
        mov rcx, 8
        call ring_init
        TEST_ASSERT_OK rax

        mov rdi, rsp
        mov rsi, test_elem1
        call ring_push
        TEST_ASSERT_OK rax
        mov rdi, rsp
        mov rsi, test_elem2
        call ring_push
        TEST_ASSERT_OK rax
        mov rdi, rsp
        mov rsi, test_elem3
        call ring_push
        TEST_ASSERT_ERROR rax  ; ENOSPC
    TEST_END

    TEST_CASE test_ring_empty
        sub rsp, 256
        mov rdi, rsp
        mov rsi, rsp
        add rsi, 32
        mov rdx, 4
        mov rcx, 8
        call ring_init
        TEST_ASSERT_OK rax

        sub rsp, 16
        mov rdi, rsp
        mov rsi, rsp
        add rsi, 8
        call ring_pop
        TEST_ASSERT_ERROR rax  ; EAGAIN
        add rsp, 16
    TEST_END

    TEST_SUITE_END

section .rodata
test_elem1: dq 0x1122334455667788
test_elem2: dq 0xAABBCCDDEEFF0011
test_elem3: dq 0x123456789ABCDEF0
test_elem4: dq 0xFEDCBA9876543210
test_elem5: dq 0x1111111111111111
test_elem6: dq 0x2222222222222222