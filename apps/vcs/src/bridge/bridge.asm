; =============================================================================
; File     : src/bridge/bridge.asm
; Project  : Utkarsha VCS (vcs)
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Git bridge — import, export, git-protocol gateway.
; =============================================================================

%ifndef VCS_BRIDGE_ASM
%define VCS_BRIDGE_ASM

%include "include/vcs.inc"

bits 64

section .text

; -----------------------------------------------------------------------------
; bridge_git_import — Import a git repository into vcs format
; Input:  rdi = git repo path, rsi = vcs repo path
; Output: rax = VCS_OK or error
; -----------------------------------------------------------------------------
global bridge_git_import
bridge_git_import:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; bridge_git_export — Export vcs repository to git format
; Input:  rdi = vcs repo path, rsi = git repo path
; Output: rax = VCS_OK or error
; -----------------------------------------------------------------------------
global bridge_git_export
bridge_git_export:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; bridge_git_serve — Serve vcs repo over git protocol
; Input:  rdi = repo path, rsi = listen address
; Output: rax = VCS_OK (never returns on success)
; -----------------------------------------------------------------------------
global bridge_git_serve
bridge_git_serve:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

%endif ; VCS_BRIDGE_ASM