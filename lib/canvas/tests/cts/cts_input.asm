; ============================================================================
; CTS Input — Input Event Conformance
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/test.inc"
%include "inc/canvas_client.inc"

section .text

global test_cts_input_suite
test_cts_input_suite:
    TEST_SUITE_BEGIN test_cts_input_suite

    TEST_CASE test_cts_input_connect
        mov rdi, CLIENT_CAP_DISPLAY | CLIENT_CAP_SURFACE
        call canvas_connect
        TEST_ASSERT_PTR rax
        mov rdi, rax
        call canvas_disconnect
    TEST_END

    TEST_SUITE_END
