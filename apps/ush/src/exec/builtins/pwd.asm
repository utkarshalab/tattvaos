; =============================================================================
; File     : apps/ush/src/exec/builtins/pwd.asm
; Project  : Utkarsha OS — Utkarsha Shell
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: pwd builtin — print working directory.
; =============================================================================

%ifndef USH_BUILTIN_PWD_ASM
%define USH_BUILTIN_PWD_ASM

%include "inc/cmd_registry.inc"

bits 64

section .data
align 16
pwd_name:   db "pwd", 0
pwd_help:   db "Print name of current working directory", 0
pwd_usage:  db "pwd", 0

section .text

CMD_FUNC(cmd_pwd):
    PROLOGUE_SAVE rbx

    mov     rdi, [ush_ctx + ush_ctx.current_dir]
    test    rdi, rdi
    jz      .pwd_root
    call    frontend_write_str
    jmp .pwd_done

.pwd_root:
    mov     al, '/'
    call    frontend_write_char

.pwd_done:
    mov     al, 0x0A
    call    frontend_write_char
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

section .rodata
align 16
pwd_entry:
    istruc cmd_entry_t
        at cmd_entry_t.name,      dq pwd_name
        at cmd_entry_t.handler,   dq cmd_pwd
        at cmd_entry_t.help,      dq pwd_help
        at cmd_entry_t.usage,     dq pwd_usage
        at cmd_entry_t.flags,     dd CMD_FLAG_BUILTIN
        at cmd_entry_t.min_args,  dd 0
        at cmd_entry_t.max_args,  dd 0
        at cmd_entry_t.category,  dq .cat_shell
        at cmd_entry_t.next,      dq 0
    iend
.cat_shell:   db "shell", 0

%endif ; USH_BUILTIN_PWD_ASM