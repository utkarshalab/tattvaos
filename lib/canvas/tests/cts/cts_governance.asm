; ============================================================================
; CTS Governance — Quota/Rate-Limit Conformance
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/test.inc"
%include "inc/canvas_client.inc"

section .text

global test_cts_governance_suite
test_cts_governance_suite:
    TEST_SUITE_BEGIN test_cts_governance_suite

    TEST_CASE test_cts_server_survives_churn
        mov rdi, CLIENT_CAP_DISPLAY | CLIENT_CAP_BUFFER | CLIENT_CAP_SURFACE | CLIENT_CAP_SHELL
        call canvas_connect
        TEST_ASSERT_PTR rax
        mov rdi, rax
        call canvas_disconnect
        ; reconnect must still work (server contained nothing global)
        mov rdi, CLIENT_CAP_DISPLAY | CLIENT_CAP_BUFFER | CLIENT_CAP_SURFACE | CLIENT_CAP_SHELL
        call canvas_connect
        TEST_ASSERT_PTR rax
        mov rdi, rax
        call canvas_disconnect
    TEST_END

    TEST_SUITE_END
