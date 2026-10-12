; ============================================================================
; RFB Unit Tests
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/test.inc"

extern rfb_check_version

section .text

global test_rfb_suite
test_rfb_suite:
    TEST_SUITE_BEGIN test_rfb_suite

    TEST_CASE test_rfb_version_check
        mov rdi, rfb_v38
        call rfb_check_version
        TEST_ASSERT_EQ rax, 1
    TEST_END

    TEST_CASE test_rfb_version_reject
        mov rdi, rfb_bad
        call rfb_check_version
        TEST_ASSERT_EQ rax, 0
    TEST_END

    TEST_SUITE_END

section .rodata
rfb_v38: db "RFB 003.008", 10
rfb_bad: db "RFB 002.000", 10
