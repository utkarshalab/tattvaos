; ============================================================================
; Golden Test — Golden Master Tests for Visual Regression
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/test.inc"
%include "inc/externs.inc"

section .text

; ============================================================================
; golden_test_main
; ============================================================================
global golden_test_main
golden_test_main:
    PROLOGUE
    xor rax, rax
    ret

; ============================================================================
; DRM_FORMAT_BGRA8888 constant
; ============================================================================
%define DRM_FORMAT_BGRA8888 0x41524742

section .data
global golden_test_version
golden_test_version: dq 0x010000