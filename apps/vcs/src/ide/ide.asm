; =============================================================================
; File     : src/ide/ide.asm
; Project  : Utkarsha VCS (vcs)
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: IDE language-server-style protocol.
; =============================================================================

%ifndef VCS_IDE_ASM
%define VCS_IDE_ASM

%include "include/vcs.inc"

bits 64

section .text

; -----------------------------------------------------------------------------
; ide_init — Initialize IDE protocol server
; Input:  rdi = listen address
; Output: rax = VCS_OK
; -----------------------------------------------------------------------------
global ide_init
ide_init:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; ide_handle_request — Handle a single IDE protocol request
; Input:  rdi = request buffer, rsi = len
; Output: rax = response length
; -----------------------------------------------------------------------------
global ide_handle_request
ide_handle_request:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

%endif ; VCS_IDE_ASM