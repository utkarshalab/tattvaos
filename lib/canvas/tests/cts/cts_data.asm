; ============================================================================
; CTS Data — Clipboard/Selection/DnD Conformance
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/test.inc"
%include "inc/canvas_client.inc"

section .text

global test_cts_data_suite
test_cts_data_suite:
    TEST_SUITE_BEGIN test_cts_data_suite

    TEST_CASE test_cts_clipboard_roundtrip
        mov rdi, CLIENT_CAP_DISPLAY | CLIENT_CAP_DATA
        call canvas_connect
        TEST_ASSERT_PTR rax
        mov rbx, rax
        mov rdi, rbx
        mov rsi, cts_mime
        mov rdx, 10
        mov rcx, cts_text
        mov r8, cts_text_len
        call canvas_clipboard_set
        TEST_ASSERT_OK rax
        mov rdi, rbx
        call canvas_disconnect
    TEST_END

    TEST_SUITE_END

section .rodata
cts_mime: db "text/plain", 0
cts_text: db "cts", 0
cts_text_len: equ $ - cts_text
