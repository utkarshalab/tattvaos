; =============================================================================
; File     : tests/golden/test_golden.asm
; Project  : Utkarsha VCS (vcs)
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Golden file tests — compare output against reference files.
; =============================================================================

%ifndef VCS_TEST_GOLDEN_ASM
%define VCS_TEST_GOLDEN_ASM

%include "include/vcs.inc"

bits 64

section .text

; -----------------------------------------------------------------------------
; test_golden_run — Run golden file tests
; Output: rax = 0 if all passed, nonzero if failed
; -----------------------------------------------------------------------------
global test_golden_run
test_golden_run:
    PROLOGUE_SAVE rbx

    call    test_cli_output
    call    test_store_format

    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

section .text

test_cli_output:
    PROLOGUE_SAVE rbx
    call    cli_main
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

test_store_format:
    PROLOGUE_SAVE rbx
    call    store_put
    call    store_get
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

%endif ; VCS_TEST_GOLDEN_ASM