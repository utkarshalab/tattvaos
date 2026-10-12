; ============================================================================
; Image Decoder Unit Tests (probe-level, no allocation)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/test.inc"

extern jpeg_probe
extern gif_probe
extern bmp_probe
extern svg_probe

section .text

global test_jpeg_suite
test_jpeg_suite:
    TEST_SUITE_BEGIN test_jpeg_suite

    TEST_CASE test_jpeg_probe_soi
        mov rdi, jpeg_soi
        mov rsi, 4
        call jpeg_probe
        TEST_ASSERT_EQ rax, 1
    TEST_END

    TEST_CASE test_jpeg_probe_reject
        mov rdi, png_sig
        mov rsi, 8
        call jpeg_probe
        TEST_ASSERT_EQ rax, 0
    TEST_END

    TEST_CASE test_gif_probe_89a
        mov rdi, gif_89a
        mov rsi, 6
        call gif_probe
        TEST_ASSERT_EQ rax, 1
    TEST_END

    TEST_CASE test_gif_probe_reject
        mov rdi, png_sig
        mov rsi, 8
        call gif_probe
        TEST_ASSERT_EQ rax, 0
    TEST_END

    TEST_CASE test_bmp_probe
        mov rdi, bmp_magic
        mov rsi, 2
        call bmp_probe
        TEST_ASSERT_EQ rax, 1
    TEST_END

    TEST_CASE test_bmp_probe_reject
        mov rdi, png_sig
        mov rsi, 8
        call bmp_probe
        TEST_ASSERT_EQ rax, 0
    TEST_END

    TEST_CASE test_svg_probe
        mov rdi, svg_doc
        mov rsi, svg_doc_len
        call svg_probe
        TEST_ASSERT_EQ rax, 1
    TEST_END

    TEST_CASE test_svg_probe_reject
        mov rdi, png_sig
        mov rsi, 8
        call svg_probe
        TEST_ASSERT_EQ rax, 0
    TEST_END

    TEST_SUITE_END

section .rodata
jpeg_soi:  db 0xFF, 0xD8, 0xFF, 0xE0
png_sig:   db 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A
gif_89a:   db 'G', 'I', 'F', '8', '9', 'a'
bmp_magic: db 'B', 'M'
svg_doc:   db '<', 's', 'v', 'g', ' ', 'x', 'm', 'l', 'n', 's', '=', '"', 'x', '"', '>'
svg_doc_len: equ $ - svg_doc
