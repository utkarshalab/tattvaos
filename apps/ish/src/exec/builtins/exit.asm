; =============================================================================
; File     : apps/ish/src/exec/builtins/exit.asm
; Project  : Tattva OS — Ishana Shell
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: exit builtin — exit the shell with optional status code.
; =============================================================================

%ifndef ISH_BUILTIN_EXIT_ASM
%define ISH_BUILTIN_EXIT_ASM

%include "inc/cmd_registry.inc"

bits 64

section .data
align 16
exit_name:   db "exit", 0
exit_help:   db "Exit the shell with a status code", 0
exit_usage:  db "exit [n]", 0

section .text

CMD_FUNC(cmd_exit):
    PROLOGUE_SAVE rbx

    mov     rbx, rdi                     ; rbx = argc

    cmp     rbx, 0
    je      .exit_no_arg
    cmp     rbx, 2
    jne     .exit_usage

    ; Parse exit code from argv[1]
    mov     rdi, [rsi + 8]
    call    str_to_int                   ; hypothetical string-to-int
    mov     [ish_ctx + ish_ctx.exit_code], eax

.exit_no_arg:
    mov     dword [ish_ctx + ish_ctx.running], 0
    mov     eax, [ish_ctx + ish_ctx.exit_code]
    EPILOGUE_RESTORE rbx
    ret

.exit_usage:
    mov     rdi, exit_usage
    call    frontend_write_str
    mov     eax, CMD_INVALID_EXIT_ARG
    EPILOGUE_RESTORE rbx
    ret

section .rodata
align 16
exit_entry:
    istruc cmd_entry_t
        at cmd_entry_t.name,      dq exit_name
        at cmd_entry_t.handler,   dq cmd_exit
        at cmd_entry_t.help,      dq exit_help
        at cmd_entry_t.usage,     dq exit_usage
        at cmd_entry_t.flags,     dd CMD_FLAG_BUILTIN
        at cmd_entry_t.min_args,  dd 0
        at cmd_entry_t.max_args,  dd 1
        at cmd_entry_t.category,  dq .cat_shell
        at cmd_entry_t.next,      dq 0
    iend
.cat_shell:   db "shell", 0

%endif ; ISH_BUILTIN_EXIT_ASM