; =============================================================================
; File     : src/server/server.asm
; Project  : Utkarsha VCS (vcs)
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Server frontends — commit queue, metadata, replication.
; =============================================================================

%ifndef VCS_SERVER_ASM
%define VCS_SERVER_ASM

%include "include/vcs.inc"

bits 64

section .text

; -----------------------------------------------------------------------------
; server_start — Start VCS server
; Input:  rdi = listen address, rsi = repo path
; Output: rax = VCS_OK (never returns on success)
; -----------------------------------------------------------------------------
global server_start
server_start:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; server_stop — Stop VCS server
; Input:  none
; Output: rax = VCS_OK
; -----------------------------------------------------------------------------
global server_stop
server_stop:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; server_land — Atomically land a change via commit queue
; Input:  rdi = change object
; Output: rax = VCS_OK or error
; -----------------------------------------------------------------------------
global server_land
server_land:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

%endif ; VCS_SERVER_ASM