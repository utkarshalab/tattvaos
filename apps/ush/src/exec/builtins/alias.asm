; =============================================================================
; File     : apps/ush/src/exec/builtins/alias.asm
; Project  : Utkarsha OS — Utkarsha Shell
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: alias builtin — define or display aliases.
; =============================================================================

%ifndef USH_BUILTIN_ALIAS_ASM
%define USH_BUILTIN_ALIAS_ASM

%include "inc/cmd_registry.inc"

bits 64

section .data
align 16
alias_name:   db "alias", 0
alias_help:   db "Define or display aliases", 0
alias_usage:  db "alias [name[=value]...]", 0

section .text

CMD_FUNC(cmd_alias):
    PROLOGUE_SAVE rbx, rcx

    cmp     rdi, 0
    je      .alias_show_all

.alias_loop:
    mov     rdx, [rsi + rbx*8]            ; argv[rbx]
    call    alias_set                     ; hypothetical: set alias

    inc     rbx
    dec     rcx
    jnz     .alias_loop
    jmp .alias_done

.alias_show_all:
    call    alias_list_all                ; hypothetical: list all aliases

.alias_done:
    xor     rax, rax
    EPILOGUE_RESTORE rbx, rcx
    ret

section .rodata
align 16
alias_entry:
    istruc cmd_entry_t
        at cmd_entry_t.name,      dq alias_name
        at cmd_entry_t.handler,   dq cmd_alias
        at cmd_entry_t.help,      dq alias_help
        at cmd_entry_t.usage,     dq alias_usage
        at cmd_entry_t.flags,     dd CMD_FLAG_BUILTIN
        at cmd_entry_t.min_args,  dd 0
        at cmd_entry_t.max_args,  dd -1
        at cmd_entry_t.category,  dq .cat_shell
        at cmd_entry_t.next,      dq 0
    iend
.cat_shell:   db "shell", 0

%endif ; USH_BUILTIN_ALIAS_ASM