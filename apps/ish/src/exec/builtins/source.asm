; =============================================================================
; File     : apps/ish/src/exec/builtins/source.asm
; Project  : Tattva OS — Ishana Shell
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: source builtin — read and execute commands from a file.
; =============================================================================

%ifndef ISH_BUILTIN_SOURCE_ASM
%define ISH_BUILTIN_SOURCE_ASM

%include "inc/cmd_registry.inc"

bits 64

section .data
align 16
source_name:   db "source", 0
source_help:   db "Read and execute commands from a file", 0
source_usage:  db "source filename", 0

section .text

CMD_FUNC(cmd_source):
    PROLOGUE_SAVE rbx

    cmp     rdi, 1
    je      .source_usage_error

    mov     rdi, [rsi + 8]                ; argv[1] = filename
    call    config_source_file            ; hypothetical: source a file

    xor     rax, rax
    jmp .source_done

.source_usage_error:
    mov     rdi, source_usage
    call    frontend_write_str
    mov     eax, CMD_INVALID_EXIT_ARG

.source_done:
    EPILOGUE_RESTORE rbx
    ret

section .rodata
align 16
source_entry:
    istruc cmd_entry_t
        at cmd_entry_t.name,      dq source_name
        at cmd_entry_t.handler,   dq cmd_source
        at cmd_entry_t.help,      dq source_help
        at cmd_entry_t.usage,     dq source_usage
        at cmd_entry_t.flags,     dd CMD_FLAG_BUILTIN
        at cmd_entry_t.min_args,  dd 1
        at cmd_entry_t.max_args,  dd 1
        at cmd_entry_t.category,  dq .cat_shell
        at cmd_entry_t.next,      dq 0
    iend
.cat_shell:   db "shell", 0

%endif ; ISH_BUILTIN_SOURCE_ASM