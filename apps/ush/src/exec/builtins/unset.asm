; =============================================================================
; File     : apps/ush/src/exec/builtins/unset.asm
; Project  : Utkarsha OS — Utkarsha Shell
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: unset builtin — remove variables or functions.
; =============================================================================

%ifndef USH_BUILTIN_UNSET_ASM
%define USH_BUILTIN_UNSET_ASM

%include "inc/cmd_registry.inc"

bits 64

section .data
align 16
unset_name:   db "unset", 0
unset_help:   db "Remove variables or functions", 0
unset_usage:  db "unset [-f] [name...]", 0

section .text

CMD_FUNC(cmd_unset):
    PROLOGUE_SAVE rbx, rcx, rdx

    mov     rbx, 1                        ; skip argv[0]
    mov     rcx, rdi                      ; argc

.unset_loop:
    test    rcx, rcx
    jz      .unset_done

    mov     rdx, [rsi + rbx*8]            ; argv[rbx]
    call    env_unset                     ; hypothetical: remove variable

    inc     rbx
    dec     rcx
    jmp .unset_loop

.unset_done:
    xor     rax, rax
    EPILOGUE_RESTORE rbx, rcx, rdx
    ret

section .rodata
align 16
unset_entry:
    istruc cmd_entry_t
        at cmd_entry_t.name,      dq unset_name
        at cmd_entry_t.handler,   dq cmd_unset
        at cmd_entry_t.help,      dq unset_help
        at cmd_entry_t.usage,     dq unset_usage
        at cmd_entry_t.flags,     dd CMD_FLAG_BUILTIN
        at cmd_entry_t.min_args,  dd 0
        at cmd_entry_t.max_args,  dd -1
        at cmd_entry_t.category,  dq .cat_shell
        at cmd_entry_t.next,      dq 0
    iend
.cat_shell:   db "shell", 0

%endif ; USH_BUILTIN_UNSET_ASM