; =============================================================================
; File     : src/merge/classifier.asm
; Project  : Utkarsha VCS (vcs)
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Content-type classifier — assembly vs binary vs opaque text.
; =============================================================================

%ifndef VCS_MERGE_CLASSIFIER_ASM
%define VCS_MERGE_CLASSIFIER_ASM

%include "include/vcs.inc"

bits 64

section .text

; -----------------------------------------------------------------------------
; classify_content — Classify file content type
; Input:  rdi = data, rsi = len, rdx = filename hint
; Output: rax = VCS_CT_* code
; -----------------------------------------------------------------------------
global classify_content
classify_content:
    PROLOGUE_SAVE rbx
    ; TODO: sniff magic bytes, check extensions, sniff content
    mov     eax, VCS_CT_BINARY
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; classify_by_extension — Classify by file extension
; Input:  rdi = filename
; Output: rax = VCS_CT_* code
; -----------------------------------------------------------------------------
global classify_by_extension
classify_by_extension:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

%endif ; VCS_MERGE_CLASSIFIER_ASM