; =============================================================================
; File     : apps/ish/src/exec/builtins/shutdown.asm
; Project  : Tattva OS — Ishana Shell
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: shutdown builtin — halt or power off the system.
; =============================================================================

%ifndef ISH_BUILTIN_SHUTDOWN_ASM
%define ISH_BUILTIN_SHUTDOWN_ASM

%include "inc/cmd_registry.inc"

bits 64

section .data
align 16
shutdown_name:   db "shutdown", 0
shutdown_help:   db "Halt the system", 0
shutdown_usage:  db "shutdown", 0

section .text

CMD_FUNC(cmd_shutdown):
    PROLOGUE_SAVE rbx

    mov     rdi, msg_shutting_down
    call    frontend_write_str

    ; Halt the CPU
    cli
    hlt

    mov     eax, CMD_GENERAL_ERROR
    EPILOGUE_RESTORE rbx
    ret

section .rodata
align 16
shutdown_entry:
    istruc cmd_entry_t
        at cmd_entry_t.name,      dq shutdown_name
        at cmd_entry_t.handler,   dq cmd_shutdown
        at cmd_entry_t.help,      dq shutdown_help
        at cmd_entry_t.usage,     dq shutdown_usage
        at cmd_entry_t.flags,     dd CMD_FLAG_BUILTIN | CMD_FLAG_DANGEROUS | CMD_FLAG_ROOT_ONLY
        at cmd_entry_t.min_args,  dd 0
        at cmd_entry_t.max_args,  dd 0
        at cmd_entry_t.category,  dq .cat_system
        at cmd_entry_t.next,      dq 0
    iend
.cat_system:   db "system", 0

msg_shutting_down: db "Shutting down Tattva OS...", 0x0A, 0

%endif ; ISH_BUILTIN_SHUTDOWN_ASM