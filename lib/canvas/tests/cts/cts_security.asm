; ============================================================================
; CTS Security — Capability Denial Conformance
; Privileged interfaces must be invisible without grants
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/test.inc"
%include "inc/canvas_client.inc"

section .text

global test_cts_security_suite
test_cts_security_suite:
    TEST_SUITE_BEGIN test_cts_security_suite

    TEST_CASE test_cts_sandboxed_has_no_capture
        mov rdi, CLIENT_CAP_DISPLAY | CLIENT_CAP_BUFFER | CLIENT_CAP_SURFACE
        call canvas_connect
        TEST_ASSERT_PTR rax
        mov rbx, rax
        mov rdi, rbx
        call canvas_get_caps
        ; privileged bits must not be granted
        mov rdx, (1 << 32) | (1 << 33) | (1 << 34) | (1 << 35)
        test rax, rdx
        jz .denied_ok
        call test_assert_fail
        jmp .denied_done
.denied_ok:
        call test_assert_pass
.denied_done:
        mov rdi, rbx
        call canvas_disconnect
    TEST_END

    TEST_SUITE_END
