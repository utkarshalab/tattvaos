; =============================================================================
; File     : src/store/segments.asm
; Project  : Utkarsha VCS (vcs)
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Object store segments — append-only segment files.
; =============================================================================

%ifndef VCS_STORE_SEGMENTS_ASM
%define VCS_STORE_SEGMENTS_ASM

%include "include/vcs.inc"

bits 64

section .text

; -----------------------------------------------------------------------------
; segment_open — Open or create a segment file
; Input:  rdi = segment path
; Output: rax = segment handle or 0
; -----------------------------------------------------------------------------
global segment_open
segment_open:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; segment_append — Append data to segment
; Input:  rdi = handle, rsi = data, rdx = len
; Output: rax = offset written or error
; -----------------------------------------------------------------------------
global segment_append
segment_append:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; segment_read — Read data from segment at offset
; Input:  rdi = handle, rsi = offset, rdx = buffer, rcx = len
; Output: rax = bytes read or error
; -----------------------------------------------------------------------------
global segment_read
segment_read:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

%endif ; VCS_STORE_SEGMENTS_ASM