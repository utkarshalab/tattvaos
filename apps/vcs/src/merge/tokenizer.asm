; =============================================================================
; File     : src/merge/tokenizer.asm
; Project  : Utkarsha VCS (vcs)
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Assembly-aware tokenizer — labels, sections, macros, directives.
; =============================================================================

%ifndef VCS_MERGE_TOKENIZER_ASM
%define VCS_MERGE_TOKENIZER_ASM

%include "include/vcs.inc"

bits 64

section .text

; -----------------------------------------------------------------------------
; tokenize_asm_line — Tokenize a single assembly line
; Input:  rdi = line, rsi = token output buffer
; Output: rax = number of tokens
; -----------------------------------------------------------------------------
global tokenize_asm_line
tokenize_asm_line:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; classify_token — Classify a token type (label, instruction, directive, etc.)
; Input:  rdi = token string
; Output: rax = token type code
; -----------------------------------------------------------------------------
global classify_token
classify_token:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

%endif ; VCS_MERGE_TOKENIZER_ASM