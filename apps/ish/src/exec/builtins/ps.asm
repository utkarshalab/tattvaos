; =============================================================================
; File     : apps/ish/src/exec/builtins/ps.asm
; Project  : Utkarsha OS — Ishana Shell
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: ps builtin — report process/fiber status.
; =============================================================================

%ifndef ISH_BUILTIN_PS_ASM
%define ISH_BUILTIN_PS_ASM

%include "inc/cmd_registry.inc"

bits 64

section .data
align 16
ps_name:    db "ps", 0
ps_help:    db "Report process/fiber status", 0
ps_usage:   db "ps", 0

ps_header:  db "  PID  TTY      TIME CMD", 0x0A
ps_idle:    db "    1  ttyS0  00:00:00 ish", 0x0A

section .text

CMD_FUNC(cmd_ps):
    PROLOGUE_SAVE rbx

    mov     rdi, ps_header
    call    frontend_write_str
    mov     rdi, ps_idle
    call    frontend_write_str

    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

section .rodata
align 16
ps_entry:
    istruc cmd_entry_t
        at cmd_entry_t.name,      dq ps_name
        at cmd_entry_t.handler,   dq cmd_ps
        at cmd_entry_t.help,      dq ps_help
        at cmd_entry_t.usage,     dq ps_usage
        at cmd_entry_t.flags,     dd CMD_FLAG_BUILTIN
        at cmd_entry_t.min_args,  dd 0
        at cmd_entry_t.max_args,  dd 0
        at cmd_entry_t.category,  dq .cat_system
        at cmd_entry_t.next,      dq 0
    iend
.cat_system:   db "system", 0

%endif ; ISH_BUILTIN_PS_ASM