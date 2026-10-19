; =============================================================================
; File     : tests/differential/test_differential.asm
; Project  : Utkarsha VCS (vcs)
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Differential tests against git for the bridge.
; =============================================================================

%ifndef VCS_TEST_DIFFERENTIAL_ASM
%define VCS_TEST_DIFFERENTIAL_ASM

%include "include/vcs.inc"

bits 64

section .text

; -----------------------------------------------------------------------------
; test_differential_run — Run differential tests vs git
; Output: rax = 0 if all passed, nonzero if failed
; -----------------------------------------------------------------------------
global test_differential_run
test_differential_run:
    PROLOGUE_SAVE rbx

    call    test_import_roundtrip
    call    test_export_roundtrip

    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

section .text

test_import_roundtrip:
    PROLOGUE_SAVE rbx
    call    bridge_git_import
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

test_export_roundtrip:
    PROLOGUE_SAVE rbx
    call    bridge_git_export
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

%endif ; VCS_TEST_DIFFERENTIAL_ASM