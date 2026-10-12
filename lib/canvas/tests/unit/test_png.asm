; ============================================================================
; PNG Unit Tests (probe + unfilter row vectors)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/test.inc"

extern png_probe
extern png_unfilter_row
extern crc32

section .text

global test_png_suite
test_png_suite:
    TEST_SUITE_BEGIN test_png_suite

    TEST_CASE test_png_probe
        mov rdi, png_sig
        mov rsi, 8
        call png_probe
        TEST_ASSERT_EQ rax, 1
    TEST_END

    TEST_CASE test_png_probe_reject
        mov rdi, not_png
        mov rsi, 8
        call png_probe
        TEST_ASSERT_EQ rax, 0
    TEST_END

    TEST_CASE test_png_unfilter_none
        ; filter 0: output == input
        sub rsp, 32
        mov byte [rsp + 0], 0  ; filter type at cur[-1]
        mov byte [rsp + 1], 10
        mov byte [rsp + 2], 20
        mov byte [rsp + 3], 30
        lea rdi, [rsp + 1]
        xor esi, esi
        mov rdx, 3
        mov rcx, 3
        call png_unfilter_row
        TEST_ASSERT_OK rax
        cmp byte [rsp + 1], 10
        jne .uf_fail
        cmp byte [rsp + 2], 20
        jne .uf_fail
        cmp byte [rsp + 3], 30
        jne .uf_fail
        call test_assert_pass
        jmp .uf_done
.uf_fail:
        call test_assert_fail
.uf_done:
        add rsp, 32
    TEST_END

    TEST_CASE test_png_unfilter_sub
        ; filter 1, bpp 3: raw(10,20,30) over zeros -> same
        sub rsp, 32
        mov byte [rsp + 0], 1
        mov byte [rsp + 1], 10
        mov byte [rsp + 2], 20
        mov byte [rsp + 3], 30
        mov byte [rsp + 4], 5
        mov byte [rsp + 5], 6
        mov byte [rsp + 6], 7
        lea rdi, [rsp + 1]
        xor esi, esi
        mov rdx, 6
        mov rcx, 3
        call png_unfilter_row
        TEST_ASSERT_OK rax
        ; second pixel = raw + first pixel
        cmp byte [rsp + 4], 15
        jne .sub_fail
        cmp byte [rsp + 5], 26
        jne .sub_fail
        cmp byte [rsp + 6], 37
        jne .sub_fail
        call test_assert_pass
        jmp .sub_done
.sub_fail:
        call test_assert_fail
.sub_done:
        add rsp, 32
    TEST_END

    TEST_CASE test_png_unfilter_bad_type
        sub rsp, 16
        mov byte [rsp + 0], 9
        mov byte [rsp + 1], 0
        lea rdi, [rsp + 1]
        xor esi, esi
        mov rdx, 1
        mov rcx, 1
        call png_unfilter_row
        TEST_ASSERT_ERROR rax
        add rsp, 16
    TEST_END

    TEST_SUITE_END

section .rodata
png_sig: db 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A
not_png: db 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07
