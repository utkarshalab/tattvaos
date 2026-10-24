; =============================================================================
; File     : apps/ush/src/exec/builtins/help.asm
; Project  : Utkarsha OS — Utkarsha Shell
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: help builtin — display help about commands.
; =============================================================================

%ifndef USH_BUILTIN_HELP_ASM
%define USH_BUILTIN_HELP_ASM

%include "inc/cmd_registry.inc"

bits 64

section .data
align 16
help_name:   db "help", 0
help_help:   db "Display information about builtin commands", 0
help_usage:  db "help [cmd]", 0

section .text

CMD_FUNC(cmd_help):
    PROLOGUE_SAVE rbx

    mov     rbx, [cmd_registry_root]
    test    rbx, rbx
    jz      .help_done

.list_cmds:
    mov     rdi, [rbx + cmd_entry_t.name]
    call    frontend_write_str
    mov     al, ' '
    call    frontend_write_char
    mov     rdi, [rbx + cmd_entry_t.help]
    call    frontend_write_str
    mov     al, 0x0A
    call    frontend_write_char
    mov     rbx, [rbx + cmd_entry_t.next]
    test    rbx, rbx
    jnz     .list_cmds

.help_done:
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

section .rodata
align 16
help_entry:
    istruc cmd_entry_t
        at cmd_entry_t.name,      dq help_name
        at cmd_entry_t.handler,   dq cmd_help
        at cmd_entry_t.help,      dq help_help
        at cmd_entry_t.usage,     dq help_usage
        at cmd_entry_t.flags,     dd CMD_FLAG_BUILTIN
        at cmd_entry_t.min_args,  dd 0
        at cmd_entry_t.max_args,  dd 1
        at cmd_entry_t.category,  dq .cat_shell
        at cmd_entry_t.next,      dq 0
    iend
.cat_shell:   db "shell", 0

%endif ; USH_BUILTIN_HELP_ASM