; =============================================================================
; File     : apps/ish/lib/cmd/fs/ls.asm
; Project  : Utkarsha OS — Ishana Shell
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: ls command library — list directory contents.
; Callable from shell or any app via CMD_FUNC ABI.
; =============================================================================

%ifndef ISH_LS_ASM
%define ISH_LS_ASM

%include "inc/cmd_registry.inc"
%include "lib/str/str.asm"

bits 64

section .data
align 16
ls_name:    db "ls", 0
ls_help:    db "List directory contents", 0
ls_usage:   db "ls [path]", 0

section .text

CMD_FUNC(cmd_ls):
    PROLOGUE_SAVE rbx

    ; Default to current directory if no argument
    cmp     rdi, 0
    je      .ls_current

    mov     rdi, [rsi + 8]                ; argv[1] = path
    call    fs_list_directory             ; hypothetical: list directory

    xor     rax, rax
    jmp .ls_done

.ls_current:
    mov     rdi, .dot                     ; "."
    call    fs_list_directory

    xor     rax, rax

.ls_done:
    EPILOGUE_RESTORE rbx
    ret

section .rodata
align 16
.dot:         db ".", 0

ls_entry:
    istruc cmd_entry_t
        at cmd_entry_t.name,      dq ls_name
        at cmd_entry_t.handler,   dq cmd_ls
        at cmd_entry_t.help,      dq ls_help
        at cmd_entry_t.usage,     dq ls_usage
        at cmd_entry_t.flags,     dd CMD_FLAG_BUILTIN
        at cmd_entry_t.min_args,  dd 0
        at cmd_entry_t.max_args,  dd 1
        at cmd_entry_t.category,  dq .cat_fs
        at cmd_entry_t.next,      dq 0
    iend
.cat_fs:      db "fs", 0

%endif ; ISH_LS_ASM