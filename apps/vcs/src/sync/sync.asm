; =============================================================================
; File     : src/sync/sync.asm
; Project  : Utkarsha VCS (vcs)
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Sync client — partial fetch, prefetch, resumable transfer.
; =============================================================================

%ifndef VCS_SYNC_ASM
%define VCS_SYNC_ASM

%include "include/vcs.inc"

bits 64

section .text

; -----------------------------------------------------------------------------
; sync_fetch — Fetch objects from remote
; Input:  rdi = remote URL, rsi = object list, rdx = count
; Output: rax = VCS_OK or error
; -----------------------------------------------------------------------------
global sync_fetch
sync_fetch:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; sync_push — Push objects to remote
; Input:  rdi = remote URL, rsi = object list, rdx = count
; Output: rax = VCS_OK or error
; -----------------------------------------------------------------------------
global sync_push
sync_push:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; sync_partial — Partial (lazy) fetch of objects on demand
; Input:  rdi = object hash
; Output: rax = VCS_OK or error
; -----------------------------------------------------------------------------
global sync_partial
sync_partial:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; sync_prefetch — Prefetch objects likely to be needed
; Input:  rdi = object list, rsi = count
; Output: rax = VCS_OK
; -----------------------------------------------------------------------------
global sync_prefetch
sync_prefetch:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

%endif ; VCS_SYNC_ASM