; =============================================================================
; File     : src/ufs/ufs.asm
; Project  : Utkarsha VCS (vcs)
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: UFS integration — snapshots, journal, subtree hashes, hydration.
; =============================================================================

%ifndef VCS_UFS_ASM
%define VCS_UFS_ASM

%include "include/vcs.inc"

bits 64

section .bss
align 16
ufs_handle:   resq 1      ; UFS connection handle

section .text

; -----------------------------------------------------------------------------
; ufs_init — Initialize UFS connection
; Output: rax = VCS_OK
; -----------------------------------------------------------------------------
global ufs_init
ufs_init:
    PROLOGUE_SAVE rbx
    ; TODO: open UFS channel, get handle
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; ufs_snapshot_create — Create a UFS snapshot
; Input:  rdi = source path, rsi = snapshot name
; Output: rax = VCS_OK or error
; -----------------------------------------------------------------------------
global ufs_snapshot_create
ufs_snapshot_create:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; ufs_snapshot_delete — Delete a UFS snapshot
; Input:  rdi = snapshot name
; Output: rax = VCS_OK or error
; -----------------------------------------------------------------------------
global ufs_snapshot_delete
ufs_snapshot_delete:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; ufs_subtree_hash — Get subtree hash for a path
; Input:  rdi = path, rsi = output hash buffer (32 bytes)
; Output: rax = VCS_OK or error
; -----------------------------------------------------------------------------
global ufs_subtree_hash
ufs_subtree_hash:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; ufs_journal_cursor — Get change journal cursor
; Input:  rdi = output cursor buffer
; Output: rax = VCS_OK or error
; -----------------------------------------------------------------------------
global ufs_journal_cursor
ufs_journal_cursor:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; ufs_journal_read — Read changes from journal since cursor
; Input:  rdi = cursor, rsi = output buffer, rdx = max entries
; Output: rax = number of entries read
; -----------------------------------------------------------------------------
global ufs_journal_read
ufs_journal_read:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; ufs_hydrate — Lazy-hydrate a file (fetch contents on first read)
; Input:  rdi = file path
; Output: rax = VCS_OK or error
; -----------------------------------------------------------------------------
global ufs_hydrate
ufs_hydrate:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

%endif ; VCS_UFS_ASM