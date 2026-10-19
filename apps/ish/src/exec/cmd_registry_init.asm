; =============================================================================
; File     : apps/ish/src/exec/cmd_registry_init.asm
; Project  : Tattva OS — Ishana Shell
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Register all builtin commands at shell startup.
; =============================================================================

%ifndef ISH_CMD_REGISTRY_INIT_ASM
%define ISH_CMD_REGISTRY_INIT_ASM

%include "inc/cmd_registry.inc"

bits 64

section .text

; -----------------------------------------------------------------------------
; cmd_registry_init — Register all builtin commands
; Input:  none
; Output: none
; -----------------------------------------------------------------------------
global cmd_registry_init
cmd_registry_init:
    PROLOGUE_SAVE rbx

    xor     eax, eax
    mov     [cmd_registry_root], eax

    ; Register builtins (order doesn't matter for linear lookup)
    mov     rdi, echo_entry
    call    exec_register_command

    mov     rdi, cd_entry
    call    exec_register_command

    mov     rdi, pwd_entry
    call    exec_register_command

    mov     rdi, exit_entry
    call    exec_register_command

    mov     rdi, help_entry
    call    exec_register_command

    mov     rdi, export_entry
    call    exec_register_command

    mov     rdi, unset_entry
    call    exec_register_command

    mov     rdi, set_entry
    call    exec_register_command

    mov     rdi, read_entry
    call    exec_register_command

    mov     rdi, history_entry
    call    exec_register_command

    mov     rdi, source_entry
    call    exec_register_command

    mov     rdi, alias_entry
    call    exec_register_command

    mov     rdi, unalias_entry
    call    exec_register_command

    mov     rdi, jobs_entry
    call    exec_register_command

    mov     rdi, fg_entry
    call    exec_register_command

    mov     rdi, bg_entry
    call    exec_register_command

    mov     rdi, kill_entry
    call    exec_register_command

    mov     rdi, reboot_entry
    call    exec_register_command

    mov     rdi, shutdown_entry
    call    exec_register_command

    mov     rdi, uname_entry
    call    exec_register_command

    mov     rdi, whoami_entry
    call    exec_register_command

    mov     rdi, id_entry
    call    exec_register_command

    mov     rdi, date_entry
    call    exec_register_command

    mov     rdi, ps_entry
    call    exec_register_command

    EPILOGUE_RESTORE rbx
    ret

%endif ; ISH_CMD_REGISTRY_INIT_ASM