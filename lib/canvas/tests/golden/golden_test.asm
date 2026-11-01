; ============================================================================
; Golden Test — Golden Master Tests for Visual Regression
; ============================================================================
; The image entry on Utkarsha; the frames are in tests/unit/test_golden.asm,
; which also runs on the host.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

extern test_golden_suite
extern ut_task_exit

section .text

; ============================================================================
; golden_test_main
; ============================================================================
global golden_test_main
golden_test_main:
    and rsp, -16
    call test_golden_suite
    mov rdi, rax
    call ut_task_exit

section .data
global golden_test_version
golden_test_version: dq 0x010100
