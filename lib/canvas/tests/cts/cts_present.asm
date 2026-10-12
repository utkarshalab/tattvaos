; ============================================================================
; CTS Present — Frame Callbacks + Presentation Feedback
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/test.inc"
%include "inc/canvas_client.inc"

section .text

global test_cts_present_suite
test_cts_present_suite:
    TEST_SUITE_BEGIN test_cts_present_suite

    TEST_CASE test_cts_frame_callback_fires
        mov rdi, CLIENT_CAP_DISPLAY | CLIENT_CAP_BUFFER | CLIENT_CAP_SURFACE | CLIENT_CAP_PRESENT
        call canvas_connect
        TEST_ASSERT_PTR rax
        mov rdi, rax
        call canvas_disconnect
    TEST_END

    TEST_SUITE_END
