; =============================================================================
; File     : apps/ish/src/exec/builtins/bg.asm
; Project  : Utkarsha OS — Ishana Shell
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: bg builtin — run job in background.
; =============================================================================

%ifndef ISH_BUILTIN_BG_ASM
%define ISH_BUILTIN_BG_ASM

%include "inc/cmd_registry.inc"

bits 64

section .data
align 16
bg_name:    db "bg", 0
bg_help:    db "Run job in background", 0
bg_usage:   db "bg [job]", 0

section .text

CMD_FUNC(cmd_bg):
    PROLOGUE_SAVE rbx

    mov     rbx, rdi                      ; argc
    cmp     rbx, 1
    je      .bg_current

    cmp     rbx, 2
    jne     .bg_usage

    mov     rdi, [rsi + 8]
    call    job_run_background            ; hypothetical: run job in background

    xor     rax, rax
    jmp .bg_done

.bg_current:
    call    job_run_current_background

.bg_done:
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

.bg_usage:
    mov     rdi, bg_usage
    call    frontend_write_str
    mov     eax, CMD_INVALID_EXIT_ARG
    EPILOGUE_RESTORE rbx
    ret

section .rodata
align 16
bg_entry:
    istruc cmd_entry_t
        at cmd_entry_t.name,      dq bg_name
        at cmd_entry_t.handler,   dq cmd_bg
        at cmd_entry_t.help,      dq bg_help
        at cmd_entry_t.usage,     dq bg_usage
        at cmd_entry_t.flags,     dd CMD_FLAG_BUILTIN
        at cmd_entry_t.min_args,  dd 0
        at cmd_entry_t.max_args,  dd 1
        at cmd_entry_t.category,  dq .cat_shell
        at cmd_entry_t.next,      dq 0
    iend
.cat_shell:   db "shell", 0

%endif ; ISH_BUILTIN_BG_ASM