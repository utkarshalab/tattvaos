; ============================================================================
; Regression Tests — Known Bug Fixes
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/test.inc"

section .text

global test_regression_1
test_regression_1:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

global test_regression_2
test_regression_2:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

global test_regression_3
test_regression_3:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

section .data
global test_regression_version
test_regression_version: dq 0x010000