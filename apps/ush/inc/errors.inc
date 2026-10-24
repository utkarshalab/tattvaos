; =============================================================================
; File     : apps/ush/inc/errors.inc
; Project  : Utkarsha OS — Utkarsha Shell
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Shell-specific error messages and codes.
; =============================================================================

%ifndef USH_ERRORS_INC
%define USH_ERRORS_INC

%include "inc/ush.inc"

; -----------------------------------------------------------------------------
; Parser Errors
; -----------------------------------------------------------------------------
USH_ERR_SYNTAX            equ 200
USH_ERR_UNBALANCED_QUOTE  equ 201
USH_ERR_TOO_MANY_ARGS     equ 202
USH_ERR_PIPE_SYNTAX       equ 203

; -----------------------------------------------------------------------------
; Executor Errors
; -----------------------------------------------------------------------------
USH_ERR_EXEC_FAILED       equ 210
USH_ERR_EXEC_NO_MEMORY    equ 211
USH_ERR_EXEC_NOT_EXECUTABLE equ 212

; -----------------------------------------------------------------------------
; Job Control Errors
; -----------------------------------------------------------------------------
USH_ERR_JOB_NOT_FOUND     equ 220
USH_ERR_JOB_INVALID_STATE equ 221

; -----------------------------------------------------------------------------
; Environment Errors
; -----------------------------------------------------------------------------
USH_ERR_ENV_READONLY      equ 230
USH_ERR_ENV_NOT_FOUND     equ 231
USH_ERR_ENV_OUT_OF_SPACE  equ 232

%endif ; USH_ERRORS_INC