; =============================================================================
; File     : apps/ush/inc/config.inc
; Project  : Utkarsha OS — Utkarsha Shell
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: .ushrc configuration file structures.
; =============================================================================

%ifndef USH_CONFIG_INC
%define USH_CONFIG_INC

%include "inc/ush.inc"

; -----------------------------------------------------------------------------
; Config Directive Types
; -----------------------------------------------------------------------------
CONFIG_DIRECTIVE_SET      equ 0      ; KEY=VALUE
CONFIG_DIRECTIVE_ALIAS    equ 1      ; alias name=value
CONFIG_DIRECTIVE_PROMPT   equ 2      ; prompt=string
CONFIG_DIRECTIVE_SOURCE   equ 3      ; source path

; -----------------------------------------------------------------------------
; Config Entry
; -----------------------------------------------------------------------------
struc config_entry_t
    .magic        resd 1      ; 0x43464701 ("CFG\x01")
    .type         resd 1      ; CONFIG_DIRECTIVE_*
    .key          resq 1
    .value        resq 1
    .next         resq 1
endstruc

CONFIG_ENTRY_SIZE         equ 40

; -----------------------------------------------------------------------------
; Config File Paths
; -----------------------------------------------------------------------------
CONFIG_SYSTEM_USHRC       db "/etc/ushrc", 0
CONFIG_USER_USHRC         db "~/.ushrc", 0

%endif ; USH_CONFIG_INC