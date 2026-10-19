; =============================================================================
; File     : apps/ish/src/exec/builtins/read.asm
; Project  : Tattva OS — Ishana Shell
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: read builtin — read a line from stdin into a variable.
; =============================================================================

%ifndef ISH_BUILTIN_READ_ASM
%define ISH_BUILTIN_READ_ASM

%include "inc/cmd_registry.inc"
%include "lib/str/str.asm"

bits 64

section .data
align 16
read_name:   db "read", 0
read_help:   db "Read a line from standard input", 0
read_usage:  db "read [name]", 0

section .bss
align 16
read_buf:    resb ISH_MAX_LINE_LEN

section .text

CMD_FUNC(cmd_read):
    PROLOGUE_SAVE rbx, rcx

    mov     rdi, read_buf
    mov     rsi, ISH_MAX_LINE_LEN
    call    frontend_read_line            ; rax = bytes read

    cmp     rax, -1
    je      .read_eof

    test    rax, rax
    jz      .read_empty

    ; Store into variable (argv[1] if provided)
    cmp     rdi, 1
    jl      .read_done
    mov     rdx, [rsi + 8]                ; argv[1] = variable name
    call    env_set_var                   ; hypothetical: set env var from read_buf

.read_empty:
    xor     rax, rax
    jmp .read_done

.read_eof:
    mov     eax, ISH_EXIT_EOF

.read_done:
    EPILOGUE_RESTORE rbx, rcx
    ret

section .rodata
align 16
read_entry:
    istruc cmd_entry_t
        at cmd_entry_t.name,      dq read_name
        at cmd_entry_t.handler,   dq cmd_read
        at cmd_entry_t.help,      dq read_help
        at cmd_entry_t.usage,     dq read_usage
        at cmd_entry_t.flags,     dd CMD_FLAG_BUILTIN
        at cmd_entry_t.min_args,  dd 0
        at cmd_entry_t.max_args,  dd 1
        at cmd_entry_t.category,  dq .cat_shell
        at cmd_entry_t.next,      dq 0
    iend
.cat_shell:   db "shell", 0

%endif ; ISH_BUILTIN_READ_ASM