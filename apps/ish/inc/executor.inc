; =============================================================================
; File     : apps/ish/inc/executor.inc
; Project  : Tattva OS — Ishana Shell
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Executor constants and dispatcher structures.
; =============================================================================

%ifndef EXECUTOR_INC
%define EXECUTOR_INC

%include "inc/ish.inc"

; -----------------------------------------------------------------------------
; Dispatcher Modes
; -----------------------------------------------------------------------------
EXEC_MODE_FOREGROUND      equ 0   ; Wait for command to finish
EXEC_MODE_BACKGROUND      equ 1   ; Run & return immediately
EXEC_MODE_PIPE            equ 2   ; Command is part of a pipeline (future)

; -----------------------------------------------------------------------------
; External Command Load Result
; -----------------------------------------------------------------------------
EXT_LOAD_SUCCESS          equ 0
EXT_LOAD_NOT_FOUND        equ 1
EXT_LOAD_INVALID_FORMAT   equ 2
EXT_LOAD_OUT_OF_MEMORY    equ 3

%endif ; EXECUTOR_INC