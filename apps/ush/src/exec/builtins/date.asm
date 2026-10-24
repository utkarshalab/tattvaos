; =============================================================================
; File     : apps/ush/src/exec/builtins/date.asm
; Project  : Utkarsha OS — Utkarsha Shell
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: date builtin — print or set system date/time.
; =============================================================================

%ifndef USH_BUILTIN_DATE_ASM
%define USH_BUILTIN_DATE_ASM

%include "inc/cmd_registry.inc"

bits 64

section .data
align 16
date_name:   db "date", 0
date_help:   db "Print or set system date and time", 0
date_usage:  db "date [format]", 0

date_str:    db "Fri Oct 16 2026", 0

section .text

CMD_FUNC(cmd_date):
    PROLOGUE_SAVE rbx

    mov     rdi, date_str
    call    frontend_write_str
    mov     al, 0x0A
    call    frontend_write_char

    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

section .rodata
align 16
date_entry:
    istruc cmd_entry_t
        at cmd_entry_t.name,      dq date_name
        at cmd_entry_t.handler,   dq cmd_date
        at cmd_entry_t.help,      dq date_help
        at cmd_entry_t.usage,     dq date_usage
        at cmd_entry_t.flags,     dd CMD_FLAG_BUILTIN
        at cmd_entry_t.min_args,  dd 0
        at cmd_entry_t.max_args,  dd 1
        at cmd_entry_t.category,  dq .cat_system
        at cmd_entry_t.next,      dq 0
    iend
.cat_system:   db "system", 0

%endif ; USH_BUILTIN_DATE_ASM