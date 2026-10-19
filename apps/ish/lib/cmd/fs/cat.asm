; =============================================================================
; File     : apps/ish/lib/cmd/fs/cat.asm
; Project  : Tattva OS — Ishana Shell
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: cat command library — concatenate and print files.
; =============================================================================

%ifndef ISH_CAT_ASM
%define ISH_CAT_ASM

%include "inc/cmd_registry.inc"
%include "lib/str/str.asm"

bits 64

section .data
align 16
cat_name:    db "cat", 0
cat_help:    db "Concatenate and print files", 0
cat_usage:   db "cat [file...]", 0

section .text

CMD_FUNC(cmd_cat):
    PROLOGUE_SAVE rbx, rcx

    mov     rbx, 1                        ; skip argv[0]
    mov     rcx, rdi                      ; argc

    test    rcx, rcx
    jz      .cat_no_args

.cat_loop:
    mov     rdi, [rsi + rbx*8]            ; filename
    call    fs_cat_file                   ; hypothetical: print file contents

    inc     rbx
    dec     rcx
    jnz     .cat_loop

    xor     rax, rax
    jmp .cat_done

.cat_no_args:
    ; Read from stdin (stdin not implemented yet)
    mov     rdi, msg_cat_stdin
    call    frontend_write_str
    mov     eax, CMD_GENERAL_ERROR

.cat_done:
    EPILOGUE_RESTORE rbx, rcx
    ret

section .rodata
align 16
msg_cat_stdin:  db "ish: cat: reading from stdin not yet implemented", 0x0A, 0

cat_entry:
    istruc cmd_entry_t
        at cmd_entry_t.name,      dq cat_name
        at cmd_entry_t.handler,   dq cmd_cat
        at cmd_entry_t.help,      dq cat_help
        at cmd_entry_t.usage,     dq cat_usage
        at cmd_entry_t.flags,     dd CMD_FLAG_BUILTIN
        at cmd_entry_t.min_args,  dd 1
        at cmd_entry_t.max_args,  dd -1
        at cmd_entry_t.category,  dq .cat_fs
        at cmd_entry_t.next,      dq 0
    iend
.cat_fs:      db "fs", 0

%endif ; ISH_CAT_ASM