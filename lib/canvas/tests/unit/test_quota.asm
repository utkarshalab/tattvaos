; ============================================================================
; Quota Unit Tests
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/test.inc"

extern quota_check_mem
extern quota_alloc_mem
extern quota_free_mem
extern quota_check_surfs
extern quota_alloc_surf
extern quota_free_surf
extern quota_check_bufs
extern quota_alloc_buf
extern quota_free_buf
extern ratelimit_check_msg
extern ratelimit_is_throttled
extern ratelimit_reset

section .text

global test_quota_suite
test_quota_suite:
    TEST_SUITE_BEGIN test_quota_suite

    ; Quota struct on stack (56 bytes, zeroed)
    TEST_CASE test_quota_mem_ok
        sub rsp, 64
        mov rdi, rsp
        mov rcx, 7
        xor rax, rax
.zero1:
        mov qword [rdi + rax * 8], 0
        inc rax
        cmp rax, rcx
        jb .zero1
        mov qword [rsp + 0], 1024    ; max_mem
        mov qword [rsp + 8], 512     ; used_mem
        mov rdi, rsp
        mov rsi, 256
        call quota_check_mem
        TEST_ASSERT_OK rax
        add rsp, 64
    TEST_END

    TEST_CASE test_quota_mem_exceeded
        sub rsp, 64
        mov rdi, rsp
        mov rcx, 7
        xor rax, rax
.zero2:
        mov qword [rdi + rax * 8], 0
        inc rax
        cmp rax, rcx
        jb .zero2
        mov qword [rsp + 0], 1024
        mov qword [rsp + 8], 900
        mov rdi, rsp
        mov rsi, 256
        call quota_check_mem
        TEST_ASSERT_ERROR rax
        add rsp, 64
    TEST_END

    TEST_CASE test_quota_mem_unlimited
        sub rsp, 64
        mov rdi, rsp
        mov rcx, 7
        xor rax, rax
.zero3:
        mov qword [rdi + rax * 8], 0
        inc rax
        cmp rax, rcx
        jb .zero3
        mov qword [rsp + 0], 0       ; unlimited
        mov qword [rsp + 8], 999999
        mov rdi, rsp
        mov rsi, 1000000
        call quota_check_mem
        TEST_ASSERT_OK rax
        add rsp, 64
    TEST_END

    TEST_CASE test_quota_surf_ok
        sub rsp, 64
        mov rdi, rsp
        mov rcx, 7
        xor rax, rax
.zero4:
        mov qword [rdi + rax * 8], 0
        inc rax
        cmp rax, rcx
        jb .zero4
        mov dword [rsp + 16], 4      ; max_surfs
        mov dword [rsp + 20], 3      ; used_surfs
        mov rdi, rsp
        call quota_check_surfs
        TEST_ASSERT_OK rax
        call quota_alloc_surf
        TEST_ASSERT_OK rax
        mov rdi, rsp
        call quota_check_surfs
        TEST_ASSERT_ERROR rax
        add rsp, 64
    TEST_END

    TEST_CASE test_quota_buf_alloc_free
        sub rsp, 64
        mov rdi, rsp
        mov rcx, 7
        xor rax, rax
.zero5:
        mov qword [rdi + rax * 8], 0
        inc rax
        cmp rax, rcx
        jb .zero5
        mov dword [rsp + 24], 2      ; max_bufs
        mov dword [rsp + 28], 0      ; used_bufs
        mov rdi, rsp
        call quota_alloc_buf
        TEST_ASSERT_OK rax
        call quota_alloc_buf
        TEST_ASSERT_OK rax
        call quota_alloc_buf
        TEST_ASSERT_ERROR rax
        call quota_free_buf
        TEST_ASSERT_OK rax
        call quota_check_bufs
        TEST_ASSERT_OK rax
        add rsp, 64
    TEST_END

    TEST_SUITE_END
