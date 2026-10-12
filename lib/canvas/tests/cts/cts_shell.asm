; ============================================================================
; CTS Shell — Toplevel/Popup/Layer Conformance
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/test.inc"
%include "inc/canvas_client.inc"

section .text

global test_cts_shell_suite
test_cts_shell_suite:
    TEST_SUITE_BEGIN test_cts_shell_suite

    TEST_CASE test_cts_toplevel_create
        mov rdi, CLIENT_CAP_DISPLAY | CLIENT_CAP_BUFFER | CLIENT_CAP_SURFACE | CLIENT_CAP_SHELL
        call canvas_connect
        TEST_ASSERT_PTR rax
        mov rbx, rax
        mov rdi, rbx
        call canvas_surface_create
        TEST_ASSERT_PTR rax
        mov rdi, rbx
        mov rsi, rax
        call canvas_toplevel_create
        TEST_ASSERT_PTR rax
        mov rdi, rbx
        call canvas_disconnect
    TEST_END

    TEST_SUITE_END
