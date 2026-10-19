; =============================================================================
; File     : apps/ish/src/exec/builtins/uname.asm
; Project  : Tattva OS — Ishana Shell
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: uname builtin — print system information.
; =============================================================================

%ifndef ISH_BUILTIN_UNAME_ASM
%define ISH_BUILTIN_UNAME_ASM

%include "inc/cmd_registry.inc"

bits 64

section .data
align 16
uname_name:   db "uname", 0
uname_help:   db "Print system information", 0
uname_usage:  db "uname [option]", 0

uname_os:     db "Tattva OS", 0
uname_arch:   db "x86-64", 0
uname_kernel: db "1.0.0", 0

section .text

CMD_FUNC(cmd_uname):
    PROLOGUE_SAVE rbx

    mov     rdi, uname_os
    call    frontend_write_str
    mov     rdi, .space
    call    frontend_write_char
    mov     rdi, uname_arch
    call    frontend_write_str
    mov     rdi, .space
    call    frontend_write_char
    mov     rdi, uname_kernel
    call    frontend_write_str
    mov     al, 0x0A
    call    frontend_write_char

    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

section .rodata
align 16
.space:       db " ", 0

uname_entry:
    istruc cmd_entry_t
        at cmd_entry_t.name,      dq uname_name
        at cmd_entry_t.handler,   dq cmd_uname
        at cmd_entry_t.help,      dq uname_help
        at cmd_entry_t.usage,     dq uname_usage
        at cmd_entry_t.flags,     dd CMD_FLAG_BUILTIN
        at cmd_entry_t.min_args,  dd 0
        at cmd_entry_t.max_args,  dd 1
        at cmd_entry_t.category,  dq .cat_system
        at cmd_entry_t.next,      dq 0
    iend
.cat_system:   db "system", 0

%endif ; ISH_BUILTIN_UNAME_ASM