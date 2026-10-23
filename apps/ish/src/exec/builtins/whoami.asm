; =============================================================================
; File     : apps/ish/src/exec/builtins/whoami.asm
; Project  : Utkarsha OS — Ishana Shell
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: whoami builtin — print current user.
; =============================================================================

%ifndef ISH_BUILTIN_WHOAMI_ASM
%define ISH_BUILTIN_WHOAMI_ASM

%include "inc/cmd_registry.inc"

bits 64

section .data
align 16
whoami_name:   db "whoami", 0
whoami_help:   db "Print current user name", 0
whoami_usage:  db "whoami", 0

whoami_user:   db "root", 0

section .text

CMD_FUNC(cmd_whoami):
    PROLOGUE_SAVE rbx

    mov     rdi, whoami_user
    call    frontend_write_str
    mov     al, 0x0A
    call    frontend_write_char

    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

section .rodata
align 16
whoami_entry:
    istruc cmd_entry_t
        at cmd_entry_t.name,      dq whoami_name
        at cmd_entry_t.handler,   dq cmd_whoami
        at cmd_entry_t.help,      dq whoami_help
        at cmd_entry_t.usage,     dq whoami_usage
        at cmd_entry_t.flags,     dd CMD_FLAG_BUILTIN
        at cmd_entry_t.min_args,  dd 0
        at cmd_entry_t.max_args,  dd 0
        at cmd_entry_t.category,  dq .cat_system
        at cmd_entry_t.next,      dq 0
    iend
.cat_system:   db "system", 0

%endif ; ISH_BUILTIN_WHOAMI_ASM