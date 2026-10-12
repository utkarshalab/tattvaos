; ============================================================================
; Arena Allocator Unit Tests
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/test.inc"

extern arena_init
extern arena_create
extern arena_alloc
extern arena_alloc_aligned
extern arena_mark
extern arena_rewind
extern arena_free_all
extern arena_used
extern arena_available
extern arena_contains
extern arena_destroy

section .text

global test_arena_suite
test_arena_suite:
    TEST_SUITE_BEGIN test_arena_suite

    ; Test 1: Basic init and alloc
    TEST_CASE test_arena_init
        ; Create arena from static memory
        sub rsp, 256
        mov rdi, rsp
        mov rsi, rsp
        add rsi, 32          ; skip arena struct
        mov rdx, 224         ; 224 bytes for data
        call arena_init
        TEST_ASSERT_OK rax
        TEST_END

    ; Test 2: Simple allocation
    TEST_CASE test_arena_alloc_simple
        sub rsp, 256
        mov rdi, rsp
        mov rsi, rsp
        add rsi, 32
        mov rdx, 224
        call arena_init
        TEST_ASSERT_OK rax

        mov rdi, rsp
        mov rsi, 64
        call arena_alloc
        TEST_ASSERT_PTR rax
        TEST_ASSERT_EQ rax, rsp + 32     ; first alloc at base
        TEST_END

    ; Test 3: Multiple allocations
    TEST_CASE test_arena_alloc_multiple
        sub rsp, 256
        mov rdi, rsp
        mov rsi, rsp
        add rsi, 32
        mov rdx, 224
        call arena_init
        TEST_ASSERT_OK rax

        mov rdi, rsp
        mov rsi, 32
        call arena_alloc
        TEST_ASSERT_PTR rax
        mov rbx, rax

        mov rdi, rsp
        mov rsi, 64
        call arena_alloc
        TEST_ASSERT_PTR rax
        ; Second alloc should be after first (aligned)
        TEST_ASSERT_EQ rax, rbx + 32
        TEST_END

    ; Test 4: Alignment
    TEST_CASE test_arena_alloc_aligned
        sub rsp, 256
        mov rdi, rsp
        mov rsi, rsp
        add rsi, 32
        mov rdx, 224
        call arena_init
        TEST_ASSERT_OK rax

        ; Allocate 1 byte, then 16-byte aligned
        mov rdi, rsp
        mov rsi, 1
        call arena_alloc
        TEST_ASSERT_PTR rax

        mov rdi, rsp
        mov rsi, 32
        mov rdx, 16
        call arena_alloc_aligned
        TEST_ASSERT_PTR rax
        TEST_ASSERT_ALIGNED rax, 16
        TEST_END

    ; Test 5: Alignment variants
    TEST_CASE test_arena_align_32
        sub rsp, 256
        mov rdi, rsp
        mov rsi, rsp
        add rsi, 32
        mov rdx, 224
        call arena_init
        TEST_ASSERT_OK rax

        mov rdi, rsp
        mov rsi, 64
        mov rdx, 32
        call arena_alloc_aligned
        TEST_ASSERT_PTR rax
        TEST_ASSERT_ALIGNED rax, 32
        TEST_END

    TEST_CASE test_arena_align_64
        sub rsp, 256
        mov rdi, rsp
        mov rsi, rsp
        add rsi, 32
        mov rdx, 224
        call arena_init
        TEST_ASSERT_OK rax

        mov rdi, rsp
        mov rsi, 64
        mov rdx, 64
        call arena_alloc_aligned
        TEST_ASSERT_PTR rax
        TEST_ASSERT_ALIGNED rax, 64
        TEST_END

    ; Test 6: Mark and rewind
    TEST_CASE test_arena_mark_rewind
        sub rsp, 256
        mov rdi, rsp
        mov rsi, rsp
        add rsi, 32
        mov rdx, 224
        call arena_init
        TEST_ASSERT_OK rax

        mov rdi, rsp
        call arena_mark
        mov rbx, rax

        mov rdi, rsp
        mov rsi, 64
        call arena_alloc
        TEST_ASSERT_PTR rax

        mov rdi, rsp
        mov rsi, rbx
        call arena_rewind
        TEST_ASSERT_OK rax

        mov rdi, rsp
        call arena_mark
        TEST_ASSERT_EQ rax, rbx
        TEST_END

    ; Test 7: Free all
    TEST_CASE test_arena_free_all
        sub rsp, 256
        mov rdi, rsp
        mov rsi, rsp
        add rsi, 32
        mov rdx, 224
        call arena_init
        TEST_ASSERT_OK rax

        mov rdi, rsp
        mov rsi, 100
        call arena_alloc
        TEST_ASSERT_PTR rax

        mov rdi, rsp
        call arena_free_all
        TEST_ASSERT_OK rax

        mov rdi, rsp
        call arena_used
        TEST_ASSERT_EQ rax, 0

        mov rdi, rsp
        call arena_available
        TEST_ASSERT_EQ rax, 224
        TEST_END

    ; Test 8: Used/Available tracking
    TEST_CASE test_arena_used_available
        sub rsp, 256
        mov rdi, rsp
        mov rsi, rsp
        add rsi, 32
        mov rdx, 224
        call arena_init
        TEST_ASSERT_OK rax

        mov rdi, rsp
        call arena_used
        TEST_ASSERT_EQ rax, 0

        mov rdi, rsp
        call arena_available
        TEST_ASSERT_EQ rax, 224

        mov rdi, rsp
        mov rsi, 50
        call arena_alloc
        TEST_ASSERT_PTR rax

        mov rdi, rsp
        call arena_used
        TEST_ASSERT_GE rax, 50
        TEST_ASSERT_LE rax, 64     ; aligned

        mov rdi, rsp
        call arena_available
        mov rbx, rax
        mov rdi, rsp
        call arena_used
        add rax, rbx
        TEST_ASSERT_EQ rax, 224
        TEST_END

    ; Test 9: Contains check
    TEST_CASE test_arena_contains
        sub rsp, 256
        mov rdi, rsp
        mov rsi, rsp
        add rsi, 32
        mov rdx, 224
        call arena_init
        TEST_ASSERT_OK rax

        mov rdi, rsp
        mov rsi, 64
        call arena_alloc
        TEST_ASSERT_PTR rax
        mov rbx, rax

        mov rdi, rsp
        mov rsi, rbx
        call arena_contains
        TEST_ASSERT_EQ rax, 1

        ; Pointer before arena
        mov rdi, rsp
        lea rsi, [rsp + 16]
        call arena_contains
        TEST_ASSERT_EQ rax, 0

        ; Pointer after arena
        mov rdi, rsp
        lea rsi, [rsp + 256]
        call arena_contains
        TEST_ASSERT_EQ rax, 0
        TEST_END

    ; Test 10: Sub-arena creation
    TEST_CASE test_arena_create_sub
        sub rsp, 512
        mov rdi, rsp
        mov rsi, rsp
        add rsi, 32
        mov rdx, 480
        call arena_init
        TEST_ASSERT_OK rax

        ; Create 128-byte sub-arena
        lea rdx, [rsp + 256]    ; child arena struct location
        mov rdi, rsp
        mov rsi, 128
        call arena_create
        TEST_ASSERT_OK rax

        ; Verify child arena works
        mov rdi, rdx
        mov rsi, 32
        call arena_alloc
        TEST_ASSERT_PTR rax

        ; Verify parent arena still works
        mov rdi, rsp
        mov rsi, 32
        call arena_alloc
        TEST_ASSERT_PTR rax
        TEST_END

    ; Test 11: OOM handling
    TEST_CASE test_arena_oom
        sub rsp, 128
        mov rdi, rsp
        mov rsi, rsp
        add rsi, 32
        mov rdx, 96
        call arena_init
        TEST_ASSERT_OK rax

        mov rdi, rsp
        mov rsi, 200
        call arena_alloc
        TEST_ASSERT_EQ rax, 0     ; OOM returns 0
        TEST_END

    ; Test 12: Zero-size allocation
    TEST_CASE test_arena_zero_size
        sub rsp, 128
        mov rdi, rsp
        mov rsi, rsp
        add rsi, 32
        mov rdx, 96
        call arena_init
        TEST_ASSERT_OK rax

        mov rdi, rsp
        mov rsi, 0
        call arena_alloc
        TEST_ASSERT_EQ rax, 0
        TEST_END

    ; Test 13: Invalid rewind
    TEST_CASE test_arena_invalid_rewind
        sub rsp, 256
        mov rdi, rsp
        mov rsi, rsp
        add rsi, 32
        mov rdx, 224
        call arena_init
        TEST_ASSERT_OK rax

        mov rdi, rsp
        mov rsi, rsp          ; before base
        call arena_rewind
        TEST_ASSERT_ERROR rax

        mov rdi, rsp
        lea rsi, [rsp + 300]  ; after limit
        call arena_rewind
        TEST_ASSERT_ERROR rax
        TEST_END

    ; Test 14: Large alignment
    TEST_CASE test_arena_large_alignment
        sub rsp, 4096
        mov rdi, rsp
        mov rsi, rsp
        add rsi, 32
        mov rdx, 4064
        call arena_init
        TEST_ASSERT_OK rax

        mov rdi, rsp
        mov rsi, 100
        mov rdx, 4096
        call arena_alloc_aligned
        TEST_ASSERT_PTR rax
        TEST_ASSERT_ALIGNED rax, 4096
        TEST_END

    TEST_SUITE_END

section .bss
    ; Test uses stack for arena memory