; =============================================================================
; File     : apps/ish/src/exec/builtins/export.asm
; Project  : Tattva OS — Ishana Shell
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: export builtin — export variables to child environments.
; =============================================================================

%ifndef ISH_BUILTIN_EXPORT_ASM
%define ISH_BUILTIN_EXPORT_ASM

%include "inc/cmd_registry.inc"

bits 64

section .data
align 16
export_name:   db "export", 0
export_help:   db "Export variables to subsequently executed commands", 0
export_usage:  db "export [name[=value]...]", 0

section .text

CMD_FUNC(cmd_export):
    PROLOGUE_SAVE rbx, rcx, rdx

    mov     rbx, 1                        ; skip argv[0]
    mov     rcx, rdi                      ; argc

.export_loop:
    test    rcx, rcx
    jz      .export_done

    mov     rdx, [rsi + rbx*8]            ; argv[rbx]
    call    env_set_exported              ; hypothetical: mark variable as exported

    inc     rbx
    dec     rcx
    jmp .export_loop

.export_done:
    xor     rax, rax
    EPILOGUE_RESTORE rbx, rcx, rdx
    ret

section .rodata
align 16
export_entry:
    istruc cmd_entry_t
        at cmd_entry_t.name,      dq export_name
        at cmd_entry_t.handler,   dq cmd_export
        at cmd_entry_t.help,      dq export_help
        at cmd_entry_t.usage,     dq export_usage
        at cmd_entry_t.flags,     dd CMD_FLAG_BUILTIN
        at cmd_entry_t.min_args,  dd 0
        at cmd_entry_t.max_args,  dd -1
        at cmd_entry_t.category,  dq .cat_shell
        at cmd_entry_t.next,      dq 0
    iend
.cat_shell:   db "shell", 0

%endif ; ISH_BUILTIN_EXPORT_ASM