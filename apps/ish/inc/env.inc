; =============================================================================
; File     : apps/ish/inc/env.inc
; Project  : Utkarsha OS — Ishana Shell
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Environment variable block structures.
; =============================================================================

%ifndef ENV_INC
%define ENV_INC

%include "inc/ish.inc"

; -----------------------------------------------------------------------------
; Environment Variable Entry
; -----------------------------------------------------------------------------
struc env_var_t
    .magic      resd 1      ; 0x454E5601 ("ENV\x01")
    .key        resq 1      ; NULL-terminated string
    .value      resq 1      ; NULL-terminated string
    .exported   resd 1      ; 1 if exported to child fibers
    .readonly   resd 1      ; 1 if read-only
    .next       resq 1
endstruc

ENV_VAR_SIZE              equ 40

; -----------------------------------------------------------------------------
; Standard Environment Variable Indices (for fast lookup)
; -----------------------------------------------------------------------------
ENV_PATH          equ 0
ENV_HOME          equ 1
ENV_USER          equ 2
ENV_SHELL         equ 3
ENV_PWD           equ 4
ENV_OLDPWD        equ 5
ENV_LANG          equ 6
ENV_TZ            equ 7
ENV_TERM          equ 8
ENV_INFERENCE_DEV equ 9      ; Utkarsha AI accelerator device
ENV_MODEL_PATH    equ 10

%endif ; ENV_INC