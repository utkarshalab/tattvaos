; =============================================================================
; File     : src/cli/cli.asm
; Project  : Utkarsha VCS (vcs)
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Command-line interface — command dispatch, JSON output.
; =============================================================================

%ifndef VCS_CLI_ASM
%define VCS_CLI_ASM

%include "include/vcs.inc"

bits 64

section .text

; -----------------------------------------------------------------------------
; cli_main — CLI entry point
; Input:  rdi = argc, rsi = argv
; Output: rax = exit code
; -----------------------------------------------------------------------------
global cli_main
cli_main:
    PROLOGUE_SAVE rbx
    ; TODO: parse args, dispatch to command handler
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; cli_cmd_clone — Lazy clone with sparse profile
; Input:  rdi = remote URL, rsi = local path
; Output: rax = exit code
; -----------------------------------------------------------------------------
global cli_cmd_clone
cli_cmd_clone:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; cli_cmd_commit — Create a commit from working copy changes
; Input:  rdi = repo path, rsi = message
; Output: rax = exit code
; -----------------------------------------------------------------------------
global cli_cmd_commit
cli_cmd_commit:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

%endif ; VCS_CLI_ASM