; =============================================================================
; File     : apps/ush/src/exec/builtins/echo.asm
; Project  : Utkarsha OS — Utkarsha Shell
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: echo builtin — write arguments to stdout.
; =============================================================================

%ifndef USH_BUILTIN_ECHO_ASM
%define USH_BUILTIN_ECHO_ASM

%include "inc/cmd_registry.inc"
%include "lib/str/str.asm"

bits 64

section .data
align 16
echo_name:    db "echo", 0
echo_help:    db "Write arguments to standard output", 0
echo_usage:   db "echo [-n] [arg...]", 0

section .text

CMD_FUNC(cmd_echo):
    PROLOGUE_SAVE rbx, rcx, rdx

    mov     rbx, 1                       ; rbx = index (skip argv[0])
    mov     rcx, rdi                     ; rcx = argc

.skip_n_flag:
    cmp     rcx, 0
    je      .echo_done
    mov     rdx, [rsi + rbx*8]
    mov     rdi, rdx
    mov     rsi, .dash_n
    call    str_ncmp                     ; compare with "-n" (2 bytes)
    test    rax, rax
    jnz     .echo_args
    inc     rbx
    dec     rcx
    jmp .skip_n_flag

.echo_args:
    test    rcx, rcx
    jz      .echo_done
    mov     rdx, [rsi + rbx*8]
    mov     rdi, rdx
    call    frontend_write_str
    inc     rbx
    dec     rcx
    test    rcx, rcx
    jz      .echo_done
    mov     rdi, .space
    call    frontend_write_char
    jmp .echo_args

.echo_done:
    cmp     byte [.suppress_newline], 0
    jne     .no_newline
    mov     rdi, .newline
    call    frontend_write_str
.no_newline:
    xor     rax, rax
    EPILOGUE_RESTORE rbx, rcx, rdx
    ret

section .bss
align 16
.suppress_newline:  resb 1

section .rodata
align 16
.dash_n:      db "-n", 0
.space:       db " ", 0
.newline:     db 0x0A, 0

echo_entry:
    istruc cmd_entry_t
        at cmd_entry_t.name,      dq echo_name
        at cmd_entry_t.handler,   dq cmd_echo
        at cmd_entry_t.help,      dq echo_help
        at cmd_entry_t.usage,     dq echo_usage
        at cmd_entry_t.flags,     dd CMD_FLAG_BUILTIN
        at cmd_entry_t.min_args,  dd 0
        at cmd_entry_t.max_args,  dd -1
        at cmd_entry_t.category,  dq .cat_shell
        at cmd_entry_t.next,      dq 0
    iend
.cat_shell:   db "shell", 0

%endif ; USH_BUILTIN_ECHO_ASM