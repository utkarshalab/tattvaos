; =============================================================================
; File     : apps/ish/src/exec/builtins/history.asm
; Project  : Utkarsha OS — Ishana Shell
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: history builtin — display command history.
; =============================================================================

%ifndef ISH_BUILTIN_HISTORY_ASM
%define ISH_BUILTIN_HISTORY_ASM

%include "inc/cmd_registry.inc"

bits 64

section .data
align 16
history_name:   db "history", 0
history_help:   db "Display the command history list", 0
history_usage:  db "history [n]", 0

section .text

CMD_FUNC(cmd_history):
    PROLOGUE_SAVE rbx

    call    history_list_all              ; hypothetical: print all history entries

    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

section .rodata
align 16
history_entry:
    istruc cmd_entry_t
        at cmd_entry_t.name,      dq history_name
        at cmd_entry_t.handler,   dq cmd_history
        at cmd_entry_t.help,      dq history_help
        at cmd_entry_t.usage,     dq history_usage
        at cmd_entry_t.flags,     dd CMD_FLAG_BUILTIN
        at cmd_entry_t.min_args,  dd 0
        at cmd_entry_t.max_args,  dd 1
        at cmd_entry_t.category,  dq .cat_shell
        at cmd_entry_t.next,      dq 0
    iend
.cat_shell:   db "shell", 0

%endif ; ISH_BUILTIN_HISTORY_ASM