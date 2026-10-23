; =============================================================================
; File     : apps/ish/inc/signals.inc
; Project  : Utkarsha OS — Ishana Shell
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Signal / trap handling definitions.
; =============================================================================

%ifndef ISH_SIGNALS_INC
%define ISH_SIGNALS_INC

%include "inc/ish.inc"

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

%endif ; ISH_SIGNALS_INC