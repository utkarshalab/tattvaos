; =============================================================================
; File     : apps/ish/src/env/config.asm
; Project  : Tattva OS — Ishana Shell
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: .ishrc configuration file parsing.
; =============================================================================

%ifndef ISH_CONFIG_ASM
%define ISH_CONFIG_ASM

%include "inc/config.inc"
%include "inc/env.inc"
%include "lib/str/str.asm"

bits 64

section .text

; -----------------------------------------------------------------------------
; config_load — Load .ishrc configuration files
; -----------------------------------------------------------------------------
global config_load
config_load:
    PROLOGUE_SAVE rbx

    ; Load system-wide config
    mov     rdi, CONFIG_SYSTEM_ISHRC
    call    config_source_file

    ; Load user config
    mov     rdi, CONFIG_USER_ISHRC
    call    config_source_file

    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; config_source_file — Source a configuration file
; Input:  rdi = file path
; Output: rax = 0 on success, -1 on failure
; -----------------------------------------------------------------------------
global config_source_file
config_source_file:
    PROLOGUE_SAVE rbx

    ; Check if file exists (simplified - stub)
    ; In a full implementation, this would open and read the file
    ; then execute each line as a command

    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; config_parse_line — Parse a single config line
; Input:  rdi = line string
; Output: rax = directive type
; -----------------------------------------------------------------------------
global config_parse_line
config_parse_line:
    PROLOGUE_SAVE rbx

    ; Check for "export KEY=VALUE"
    mov     rsi, .export_str
    call    str_ncmp                      ; compare first 6 bytes
    test    rax, rax
    jz      .config_export

    ; Check for "alias NAME=VALUE"
    mov     rsi, .alias_str
    call    str_ncmp                      ; compare first 5 bytes
    test    rax, rax
    jz      .config_alias

    ; Check for "prompt=STRING"
    mov     rsi, .prompt_str
    call    str_ncmp                      ; compare first 6 bytes
    test    rax, rax
    jz      .config_prompt

    jmp .config_unknown

.config_export:
    mov     rax, CONFIG_DIRECTIVE_SET
    jmp .config_done

.config_alias:
    mov     rax, CONFIG_DIRECTIVE_ALIAS
    jmp .config_done

.config_prompt:
    mov     rax, CONFIG_DIRECTIVE_PROMPT
    jmp .config_done

.config_unknown:
    mov     rax, -1

.config_done:
    EPILOGUE_RESTORE rbx
    ret

section .rodata
align 16
.export_str:  db "export", 0
.alias_str:   db "alias ", 0
.prompt_str:  db "prompt=", 0

%endif ; ISH_CONFIG_ASM