; =============================================================================
; File     : src/server/commit_queue.asm
; Project  : Utkarsha VCS (vcs)
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Commit queue — validate, merge, land changes atomically.
; =============================================================================

%ifndef VCS_SERVER_COMMIT_QUEUE_ASM
%define VCS_SERVER_COMMIT_QUEUE_ASM

%include "include/vcs.inc"

bits 64

section .text

; -----------------------------------------------------------------------------
; cq_enqueue — Enqueue a change for landing
; Input:  rdi = change object
; Output: rax = queue position or error
; -----------------------------------------------------------------------------
global cq_enqueue
cq_enqueue:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; cq_validate — Validate a change before landing (tests, policy, signatures)
; Input:  rdi = change object
; Output: rax = VCS_OK or error
; -----------------------------------------------------------------------------
global cq_validate
cq_validate:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; cq_land — Land all validated changes atomically
; Input:  none
; Output: rax = number of changes landed
; -----------------------------------------------------------------------------
global cq_land
cq_land:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

%endif ; VCS_SERVER_COMMIT_QUEUE_ASM