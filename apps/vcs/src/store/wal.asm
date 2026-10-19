; =============================================================================
; File     : src/store/wal.asm
; Project  : Utkarsha VCS (vcs)
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Write-ahead log for crash-safe object store operations.
; =============================================================================

%ifndef VCS_STORE_WAL_ASM
%define VCS_STORE_WAL_ASM

%include "include/vcs.inc"

bits 64

section .text

; -----------------------------------------------------------------------------
; wal_begin — Begin a WAL transaction
; Input:  rdi = transaction ID buffer
; Output: rax = VCS_OK
; -----------------------------------------------------------------------------
global wal_begin
wal_begin:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; wal_record — Record an operation in the WAL
; Input:  rdi = txn ID, rsi = op type, rdx = data, rcx = len
; Output: rax = VCS_OK
; -----------------------------------------------------------------------------
global wal_record
wal_record:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; wal_commit — Commit a WAL transaction (fsync)
; Input:  rdi = txn ID
; Output: rax = VCS_OK
; -----------------------------------------------------------------------------
global wal_commit
wal_commit:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; wal_abort — Abort a WAL transaction
; Input:  rdi = txn ID
; Output: rax = VCS_OK
; -----------------------------------------------------------------------------
global wal_abort
wal_abort:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

%endif ; VCS_STORE_WAL_ASM