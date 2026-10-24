; =============================================================================
; File     : apps/ush/inc/signals.inc
; Project  : Utkarsha OS — Utkarsha Shell
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Signal / trap handling definitions.
; =============================================================================

%ifndef USH_SIGNALS_INC
%define USH_SIGNALS_INC

%include "inc/ush.inc"

; -----------------------------------------------------------------------------
; Signal Numbers (subset relevant to shell)
; -----------------------------------------------------------------------------
SIGINT        equ 2       ; Interrupt (Ctrl-C)
SIGQUIT       equ 3       ; Quit (Ctrl-\)
SIGTERM       equ 15      ; Terminate
SIGKILL       equ 9       ; Kill (cannot trap)
SIGCHLD       equ 17      ; Child stopped/terminated

; -----------------------------------------------------------------------------
; Trap Entry
; -----------------------------------------------------------------------------
struc trap_entry_t
    .signal     resd 1
    .handler    resq 1      ; fn(signal) -> void
    .next       resq 1
endstruc

TRAP_ENTRY_SIZE           equ 24

%endif ; USH_SIGNALS_INC