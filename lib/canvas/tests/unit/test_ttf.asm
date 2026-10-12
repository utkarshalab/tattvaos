; ============================================================================
; TTF Unit Tests (probe, fixed-point helpers, flatten emit)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/test.inc"

extern ttf_probe
extern ttf_u16
extern ttf_u32
extern flatten_emit_line

section .text

global test_ttf_suite
test_ttf_suite:
    TEST_SUITE_BEGIN test_ttf_suite

    TEST_CASE test_ttf_probe_truetype
        mov rdi, ttf_v1
        mov rsi, 12
        call ttf_probe
        TEST_ASSERT_EQ rax, 1
    TEST_END

    TEST_CASE test_ttf_probe_otf
        mov rdi, ttf_otto
        mov rsi, 12
        call ttf_probe
        TEST_ASSERT_EQ rax, 1
    TEST_END

    TEST_CASE test_ttf_probe_reject
        mov rdi, ttf_bad
        mov rsi, 12
        call ttf_probe
        TEST_ASSERT_EQ rax, 0
    TEST_END

    TEST_CASE test_ttf_be16
        mov rdi, be_buf
        call ttf_u16
        cmp eax, 0x1234
        je .u16_ok
        call test_assert_fail
        jmp .u16_done
.u16_ok:
        call test_assert_pass
.u16_done:
    TEST_END

    TEST_CASE test_ttf_be32
        mov rdi, be_buf
        call ttf_u32
        cmp eax, 0x12345678
        je .u32_ok
        call test_assert_fail
        jmp .u32_done
.u32_ok:
        call test_assert_pass
.u32_done:
    TEST_END

    TEST_CASE test_flatten_emit_line
        sub rsp, 64
        ; FlattenCtx at rsp: out=rsp+32 (2 records), count=0, cap=2
        lea rax, [rsp + 32]
        mov [rsp + 0], rax
        mov qword [rsp + 8], 0
        mov qword [rsp + 16], 2
        mov rdi, rsp
        mov rsi, 100
        mov rdx, 200
        call flatten_emit_line
        TEST_ASSERT_OK rax
        cmp qword [rsp + 8], 1
        jne .fl_fail
        cmp byte [rsp + 32], 1  ; VERB_LINE
        jne .fl_fail
        call test_assert_pass
        jmp .fl_done
.fl_fail:
        call test_assert_fail
.fl_done:
        add rsp, 64
    TEST_END

    TEST_SUITE_END

section .rodata
ttf_v1:   db 0x00, 0x01, 0x00, 0x00, 0, 0, 0, 0, 0, 0, 0, 0
ttf_otto: db 'O', 'T', 'T', 'O', 0, 0, 0, 0, 0, 0, 0, 0
ttf_bad:  db 'B', 'A', 'D', '!', 0, 0, 0, 0, 0, 0, 0, 0
be_buf:   db 0x12, 0x34, 0x56, 0x78
