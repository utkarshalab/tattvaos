; =============================================================================
; File     : apps/ish/inc/errors.inc
; Project  : Utkarsha OS — Ishana Shell
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Shell-specific error messages and codes.
; =============================================================================

%ifndef ISH_ERRORS_INC
%define ISH_ERRORS_INC

%include "inc/ish.inc"

; -----------------------------------------------------------------------------
; Parser Errors
; -----------------------------------------------------------------------------
ISH_ERR_SYNTAX            equ 200
ISH_ERR_UNBALANCED_QUOTE  equ 201
ISH_ERR_TOO_MANY_ARGS     equ 202
ISH_ERR_PIPE_SYNTAX       equ 203

; -----------------------------------------------------------------------------
; Executor Errors
; -----------------------------------------------------------------------------
ISH_ERR_EXEC_FAILED       equ 210
ISH_ERR_EXEC_NO_MEMORY    equ 211
ISH_ERR_EXEC_NOT_EXECUTABLE equ 212

; -----------------------------------------------------------------------------
; Job Control Errors
; -----------------------------------------------------------------------------
ISH_ERR_JOB_NOT_FOUND     equ 220
ISH_ERR_JOB_INVALID_STATE equ 221

; -----------------------------------------------------------------------------
; Environment Errors
; -----------------------------------------------------------------------------
ISH_ERR_ENV_READONLY      equ 230
ISH_ERR_ENV_NOT_FOUND     equ 231
ISH_ERR_ENV_OUT_OF_SPACE  equ 232

%endif ; ISH_ERRORS_INC