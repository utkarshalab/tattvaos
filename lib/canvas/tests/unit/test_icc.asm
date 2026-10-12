; ============================================================================
; ICC / Color Unit Tests
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/test.inc"

extern icc_probe
extern mat3_identity
extern mat3_mul
extern trc_init_gamma
extern trc_init_linear
extern trc_apply
extern pq_to_linear
extern hlg_to_linear
extern tonemap_reinhard

section .text

global test_icc_suite
test_icc_suite:
    TEST_SUITE_BEGIN test_icc_suite

    TEST_CASE test_icc_probe_reject
        sub rsp, 144
        mov rdi, rsp
        mov rcx, 18
        xor rax, rax
.z:
        mov qword [rdi + rax * 8], 0
        inc rax
        cmp rax, rcx
        jb .z
        mov rdi, rsp
        mov rsi, 132
        call icc_probe
        TEST_ASSERT_EQ rax, 0
        add rsp, 144
    TEST_END

    TEST_CASE test_icc_probe_magic
        sub rsp, 144
        mov rdi, rsp
        mov rcx, 18
        xor rax, rax
.z2:
        mov qword [rdi + rax * 8], 0
        inc rax
        cmp rax, rcx
        jb .z2
        mov dword [rsp + 80], 0x70736361
        mov dword [rsp + 0], 132
        mov rdi, rsp
        mov rsi, 132
        call icc_probe
        TEST_ASSERT_EQ rax, 1
        add rsp, 144
    TEST_END

    TEST_CASE test_mat3_identity
        sub rsp, 48
        mov rdi, rsp
        call mat3_identity
        TEST_ASSERT_OK rax
        cmp dword [rsp + 0], 0x10000
        je .m_ok
        call test_assert_fail
        jmp .m_done
.m_ok:
        call test_assert_pass
.m_done:
        add rsp, 48
    TEST_END

    TEST_CASE test_trc_linear
        sub rsp, 64
        mov rdi, rsp
        call trc_init_linear
        TEST_ASSERT_OK rax
        mov rdi, rsp
        mov rsi, 0x8000
        call trc_apply
        TEST_ASSERT_EQ rax, 0x8000
        add rsp, 64
    TEST_END

    TEST_CASE test_pq_monotonic
        mov rdi, 0x4000
        call pq_to_linear
        mov rbx, rax
        mov rdi, 0xC000
        call pq_to_linear
        cmp rax, rbx
        ja .pq_ok
        call test_assert_fail
        jmp .pq_done
.pq_ok:
        call test_assert_pass
.pq_done:
    TEST_END

    TEST_CASE test_tonemap_reinhard_mid
        mov rdi, 0x10000
        mov rsi, 0x10000
        mov rdx, 0x10000
        call tonemap_reinhard
        ; result should be in (0, 0x10000]
        cmp rax, 0
        jbe .tm_fail
        cmp rax, 0x10000
        jbe .tm_ok
.tm_fail:
        call test_assert_fail
        jmp .tm_done
.tm_ok:
        call test_assert_pass
.tm_done:
    TEST_END

    TEST_SUITE_END
