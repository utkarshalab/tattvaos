; =============================================================================
; File     : apps/ish/src/exec/builtins/kill.asm
; Project  : Utkarsha OS — Ishana Shell
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: kill builtin — send signal to job or process.
; =============================================================================

%ifndef ISH_BUILTIN_KILL_ASM
%define ISH_BUILTIN_KILL_ASM

%include "inc/cmd_registry.inc"

bits 64

section .data
align 16
kill_name:    db "kill", 0
kill_help:    db "Send a signal to a job or process", 0
kill_usage:   db "kill [-s signal] pid...", 0

section .text

CMD_FUNC(cmd_kill):
    PROLOGUE_SAVE rbx, rcx

    mov     rbx, 1                        ; skip argv[0]
    mov     rcx, rdi                      ; argc

    test    rcx, rcx
    jz      .kill_usage

    ; Simple: just send SIGTERM to first pid argument
    mov     rdi, [rsi + rbx*8]            ; pid string
    call    job_send_signal               ; hypothetical: send signal to job

    xor     rax, rax
    jmp .kill_done

.kill_usage:
    mov     rdi, kill_usage
    call    frontend_write_str
    mov     eax, CMD_INVALID_EXIT_ARG

.kill_done:
    EPILOGUE_RESTORE rbx, rcx
    ret

section .rodata
align 16
kill_entry:
    istruc cmd_entry_t
        at cmd_entry_t.name,      dq kill_name
        at cmd_entry_t.handler,   dq cmd_kill
        at cmd_entry_t.help,      dq kill_help
        at cmd_entry_t.usage,     dq kill_usage
        at cmd_entry_t.flags,     dd CMD_FLAG_BUILTIN
        at cmd_entry_t.min_args,  dd 1
        at cmd_entry_t.max_args,  dd -1
        at cmd_entry_t.category,  dq .cat_shell
        at cmd_entry_t.next,      dq 0
    iend
.cat_shell:   db "shell", 0

%endif ; ISH_BUILTIN_KILL_ASM