; =============================================================================
; File     : apps/ish/src/exec/builtins/set.asm
; Project  : Tattva OS — Ishana Shell
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: set builtin — set shell options or display variables.
; =============================================================================

%ifndef ISH_BUILTIN_SET_ASM
%define ISH_BUILTIN_SET_ASM

%include "inc/cmd_registry.inc"

bits 64

section .data
align 16
set_name:    db "set", 0
set_help:    db "Set shell options or display variable values", 0
set_usage:   db "set [option] [name[=value]...]", 0

section .text

CMD_FUNC(cmd_set):
    PROLOGUE_SAVE rbx, rcx

    cmp     rdi, 0
    je      .set_show_all

.set_loop:
    mov     rdx, [rsi + rbx*8]
    call    env_set                       ; hypothetical: set env var

    inc     rbx
    dec     rcx
    jnz     .set_loop
    jmp .set_done

.set_show_all:
    call    env_dump_all                  ; hypothetical: dump all variables

.set_done:
    xor     rax, rax
    EPILOGUE_RESTORE rbx, rcx
    ret

section .rodata
align 16
set_entry:
    istruc cmd_entry_t
        at cmd_entry_t.name,      dq set_name
        at cmd_entry_t.handler,   dq cmd_set
        at cmd_entry_t.help,      dq set_help
        at cmd_entry_t.usage,     dq set_usage
        at cmd_entry_t.flags,     dd CMD_FLAG_BUILTIN
        at cmd_entry_t.min_args,  dd 0
        at cmd_entry_t.max_args,  dd -1
        at cmd_entry_t.category,  dq .cat_shell
        at cmd_entry_t.next,      dq 0
    iend
.cat_shell:   db "shell", 0

%endif ; ISH_BUILTIN_SET_ASM