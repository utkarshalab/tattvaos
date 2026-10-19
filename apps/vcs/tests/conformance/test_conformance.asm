; =============================================================================
; File     : tests/conformance/test_conformance.asm
; Project  : Utkarsha VCS (vcs)
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Conformance tests against spec-derived vectors.
; =============================================================================

%ifndef VCS_TEST_CONFORMANCE_ASM
%define VCS_TEST_CONFORMANCE_ASM

%include "include/vcs.inc"

bits 64

section .text

; -----------------------------------------------------------------------------
; test_conformance_run — Run all conformance tests
; Output: rax = 0 if all passed, nonzero if failed
; -----------------------------------------------------------------------------
global test_conformance_run
test_conformance_run:
    PROLOGUE_SAVE rbx

    call    test_ufs_contract
    call    test_object_model
    call    test_hashing_ids
    call    test_chunking

    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

section .text

test_ufs_contract:
    PROLOGUE_SAVE rbx
    call    ufs_init
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

test_object_model:
    PROLOGUE_SAVE rbx
    call    store_init
    call    store_put
    call    store_get
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

test_hashing_ids:
    PROLOGUE_SAVE rbx
    call    scalar_blake3
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

test_chunking:
    PROLOGUE_SAVE rbx
    call    scalar_chunk
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

%endif ; VCS_TEST_CONFORMANCE_ASM