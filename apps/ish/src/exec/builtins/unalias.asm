; =============================================================================
; File     : apps/ish/src/exec/builtins/unalias.asm
; Project  : Utkarsha OS — Ishana Shell
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: unalias builtin — remove alias definitions.
; =============================================================================

%ifndef ISH_BUILTIN_UNALIAS_ASM
%define ISH_BUILTIN_UNALIAS_ASM

%include "inc/cmd_registry.inc"

bits 64

section .data
align 16
unalias_name:   db "unalias", 0
unalias_help:   db "Remove alias definitions", 0
unalias_usage:  db "unalias [-a] [name...]", 0

section .text

CMD_FUNC(cmd_unalias):
    PROLOGUE_SAVE rbx, rcx

    mov     rbx, 1
    mov     rcx, rdi

.unalias_loop:
    test    rcx, rcx
    jz      .unalias_done

    mov     rdx, [rsi + rbx*8]
    call    alias_unset                     ; hypothetical: remove alias

    inc     rbx
    dec     rcx
    jmp .unalias_loop

.unalias_done:
    xor     rax, rax
    EPILOGUE_RESTORE rbx, rcx
    ret

section .rodata
align 16
unalias_entry:
    istruc cmd_entry_t
        at cmd_entry_t.name,      dq unalias_name
        at cmd_entry_t.handler,   dq cmd_unalias
        at cmd_entry_t.help,      dq unalias_help
        at cmd_entry_t.usage,     dq unalias_usage
        at cmd_entry_t.flags,     dd CMD_FLAG_BUILTIN
        at cmd_entry_t.min_args,  dd 0
        at cmd_entry_t.max_args,  dd -1
        at cmd_entry_t.category,  dq .cat_shell
        at cmd_entry_t.next,      dq 0
    iend
.cat_shell:   db "shell", 0

%endif ; ISH_BUILTIN_UNALIAS_ASM