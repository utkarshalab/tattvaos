; =============================================================================
; File     : src/oplog/oplog.asm
; Project  : Utkarsha VCS (vcs)
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Operation log — every command recorded, powers undo/audit.
; =============================================================================

%ifndef VCS_OPLOG_ASM
%define VCS_OPLOG_ASM

%include "include/vcs.inc"

bits 64

section .text

; -----------------------------------------------------------------------------
; oplog_append — Append an operation record
; Input:  rdi = op type, rsi = details, rdx = details len
; Output: rax = operation ID or error
; -----------------------------------------------------------------------------
global oplog_append
oplog_append:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; oplog_read — Read operations since cursor
; Input:  rdi = cursor, rsi = output buffer, rdx = max entries
; Output: rax = number of entries
; -----------------------------------------------------------------------------
global oplog_read
oplog_read:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; oplog_undo — Undo operations back to a given cursor
; Input:  rdi = target cursor
; Output: rax = VCS_OK or error
; -----------------------------------------------------------------------------
global oplog_undo
oplog_undo:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

%endif ; VCS_OPLOG_ASM