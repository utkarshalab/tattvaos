; =============================================================================
; File     : apps/ish/src/exec/builtins/reboot.asm
; Project  : Tattva OS — Ishana Shell
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: reboot builtin — reboot the system.
; =============================================================================

%ifndef ISH_BUILTIN_REBOOT_ASM
%define ISH_BUILTIN_REBOOT_ASM

%include "inc/cmd_registry.inc"

bits 64

section .data
align 16
reboot_name:   db "reboot", 0
reboot_help:   db "Reboot the system", 0
reboot_usage:  db "reboot", 0

section .text

CMD_FUNC(cmd_reboot):
    PROLOGUE_SAVE rbx

    mov     rdi, msg_rebooting
    call    frontend_write_str

    ; Triple fault to reset CPU (simple x86 reboot)
    cli
    hlt

    ; Should never reach here
    mov     eax, CMD_GENERAL_ERROR
    EPILOGUE_RESTORE rbx
    ret

section .rodata
align 16
reboot_entry:
    istruc cmd_entry_t
        at cmd_entry_t.name,      dq reboot_name
        at cmd_entry_t.handler,   dq cmd_reboot
        at cmd_entry_t.help,      dq reboot_help
        at cmd_entry_t.usage,     dq reboot_usage
        at cmd_entry_t.flags,     dd CMD_FLAG_BUILTIN | CMD_FLAG_DANGEROUS | CMD_FLAG_ROOT_ONLY
        at cmd_entry_t.min_args,  dd 0
        at cmd_entry_t.max_args,  dd 0
        at cmd_entry_t.category,  dq .cat_system
        at cmd_entry_t.next,      dq 0
    iend
.cat_system:   db "system", 0

msg_rebooting:   db "Rebooting Tattva OS...", 0x0A, 0

%endif ; ISH_BUILTIN_REBOOT_ASM