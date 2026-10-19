; =============================================================================
; File     : apps/ish/src/exec/builtins/jobs.asm
; Project  : Tattva OS — Ishana Shell
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: jobs builtin — list active jobs.
; =============================================================================

%ifndef ISH_BUILTIN_JOBS_ASM
%define ISH_BUILTIN_JOBS_ASM

%include "inc/cmd_registry.inc"

bits 64

section .data
align 16
jobs_name:   db "jobs", 0
jobs_help:   db "List active jobs", 0
jobs_usage:  db "jobs", 0

section .text

CMD_FUNC(cmd_jobs):
    PROLOGUE_SAVE rbx

    call    job_list_all                    ; hypothetical: list all jobs

    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

section .rodata
align 16
jobs_entry:
    istruc cmd_entry_t
        at cmd_entry_t.name,      dq jobs_name
        at cmd_entry_t.handler,   dq cmd_jobs
        at cmd_entry_t.help,      dq jobs_help
        at cmd_entry_t.usage,     dq jobs_usage
        at cmd_entry_t.flags,     dd CMD_FLAG_BUILTIN
        at cmd_entry_t.min_args,  dd 0
        at cmd_entry_t.max_args,  dd 0
        at cmd_entry_t.category,  dq .cat_shell
        at cmd_entry_t.next,      dq 0
    iend
.cat_shell:   db "shell", 0

%endif ; ISH_BUILTIN_JOBS_ASM