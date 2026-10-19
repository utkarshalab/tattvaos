; =============================================================================
; File     : apps/ish/src/exec/builtins/cd.asm
; Project  : Tattva OS — Ishana Shell
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: cd builtin — change working directory.
; =============================================================================

%ifndef ISH_BUILTIN_CD_ASM
%define ISH_BUILTIN_CD_ASM

%include "inc/cmd_registry.inc"
%include "lib/str/str.asm"

bits 64

section .data
align 16
cd_name:    db "cd", 0
cd_help:    db "Change the shell working directory", 0
cd_usage:   db "cd [dir]", 0

section .text

CMD_FUNC(cmd_cd):
    PROLOGUE_SAVE rbx, rsi, rdx

    mov     rbx, rdi                     ; rbx = argc
    mov     rdx, rsi                     ; rdx = argv

    cmp     rbx, 1
    je      .cd_home                     ; no args -> home directory

    cmp     rbx, 2
    jne     .cd_usage_error

    ; argv[1] is the target directory
    mov     rdi, [rdx + 8]
    call    sys_chdir                    ; hypothetical kernel chdir
    test    rax, rax
    jnz     .cd_error

    call    env_update_pwd               ; update PWD env var

    xor     rax, rax
    jmp .cd_done

.cd_home:
    call    env_get_home                 ; rax = HOME path or 0
    test    rax, rax
    jz      .cd_error_no_home
    mov     rdi, rax
    call    sys_chdir
    test    rax, rax
    jnz     .cd_error
    call    env_update_pwd
    xor     rax, rax
    jmp .cd_done

.cd_usage_error:
    mov     rdi, cd_usage
    call    frontend_write_str
    mov     eax, CMD_INVALID_EXIT_ARG
    jmp .cd_done

.cd_error_no_home:
    mov     rdi, msg_cd_no_home
    call    frontend_write_str
    mov     eax, CMD_GENERAL_ERROR
    jmp .cd_done

.cd_error:
    mov     rdi, msg_cd_failed
    call    frontend_write_str
    mov     eax, CMD_GENERAL_ERROR

.cd_done:
    EPILOGUE_RESTORE rbx, rsi, rdx
    ret

section .rodata
align 16
cd_entry:
    istruc cmd_entry_t
        at cmd_entry_t.name,      dq cd_name
        at cmd_entry_t.handler,   dq cmd_cd
        at cmd_entry_t.help,      dq cd_help
        at cmd_entry_t.usage,     dq cd_usage
        at cmd_entry_t.flags,     dd CMD_FLAG_BUILTIN
        at cmd_entry_t.min_args,  dd 0
        at cmd_entry_t.max_args,  dd 1
        at cmd_entry_t.category,  dq .cat_shell
        at cmd_entry_t.next,      dq 0
    iend
.cat_shell:   db "shell", 0

msg_cd_failed:    db "ish: cd: directory not found", 0x0A, 0
msg_cd_no_home:   db "ish: cd: HOME not set", 0x0A, 0

%endif ; ISH_BUILTIN_CD_ASM