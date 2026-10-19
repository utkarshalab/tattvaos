; =============================================================================
; File     : apps/ish/src/exec/builtins/fg.asm
; Project  : Tattva OS — Ishana Shell
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: fg builtin — bring job to foreground.
; =============================================================================

%ifndef ISH_BUILTIN_FG_ASM
%define ISH_BUILTIN_FG_ASM

%include "inc/cmd_registry.inc"

bits 64

section .data
align 16
fg_name:    db "fg", 0
fg_help:    db "Bring a job to the foreground", 0
fg_usage:   db "fg [job]", 0

section .text

CMD_FUNC(cmd_fg):
    PROLOGUE_SAVE rbx

    mov     rbx, rdi                      ; argc
    cmp     rbx, 1
    je      .fg_current                   ; no args -> current job

    cmp     rbx, 2
    jne     .fg_usage

    mov     rdi, [rsi + 8]                ; argv[1] = job spec
    call    job_bring_foreground          ; hypothetical: bring job to foreground

    xor     rax, rax
    jmp .fg_done

.fg_current:
    call    job_bring_current_foreground  ; hypothetical: bring current job

.fg_done:
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

.fg_usage:
    mov     rdi, fg_usage
    call    frontend_write_str
    mov     eax, CMD_INVALID_EXIT_ARG
    EPILOGUE_RESTORE rbx
    ret

section .rodata
align 16
fg_entry:
    istruc cmd_entry_t
        at cmd_entry_t.name,      dq fg_name
        at cmd_entry_t.handler,   dq cmd_fg
        at cmd_entry_t.help,      dq fg_help
        at cmd_entry_t.usage,     dq fg_usage
        at cmd_entry_t.flags,     dd CMD_FLAG_BUILTIN
        at cmd_entry_t.min_args,  dd 0
        at cmd_entry_t.max_args,  dd 1
        at cmd_entry_t.category,  dq .cat_shell
        at cmd_entry_t.next,      dq 0
    iend
.cat_shell:   db "shell", 0

%endif ; ISH_BUILTIN_FG_ASM