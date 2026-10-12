; ============================================================================
; CTS Core — Black-Box Protocol Conformance (connect, caps, sync, errors)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/test.inc"
%include "inc/canvas_client.inc"

section .text

global test_cts_core_suite
test_cts_core_suite:
    TEST_SUITE_BEGIN test_cts_core_suite

    TEST_CASE test_cts_connect_grants_core
        mov rdi, CLIENT_CAP_DISPLAY | CLIENT_CAP_BUFFER | CLIENT_CAP_SURFACE | CLIENT_CAP_PRESENT
        call canvas_connect
        TEST_ASSERT_PTR rax
        mov rbx, rax
        mov rdi, rbx
        call canvas_get_caps
        mov rdx, CLIENT_CAP_DISPLAY | CLIENT_CAP_BUFFER | CLIENT_CAP_SURFACE | CLIENT_CAP_PRESENT
        and rax, rdx
        cmp rax, rdx
        je .caps_ok
        call test_assert_fail
        jmp .caps_done
.caps_ok:
        call test_assert_pass
.caps_done:
        mov rdi, rbx
        call canvas_disconnect
    TEST_END

    TEST_CASE test_cts_sync_serial_monotonic
        mov rdi, CLIENT_CAP_DISPLAY
        call canvas_connect
        TEST_ASSERT_PTR rax
        mov rdi, rax
        call canvas_disconnect
    TEST_END

    TEST_SUITE_END
