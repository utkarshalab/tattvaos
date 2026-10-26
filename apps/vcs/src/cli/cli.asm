; Callable CLI; System V AMD64, no console or filesystem dependencies.
%include "include/vcs.inc"
bits 64
default rel
section .rodata
help_text: db 'Usage: vcs <command>',10,'Commands: help, version, init, status, commit, clone, log',10,'Repository operations are not implemented yet.',10,0
version_text: db 'Utkarsha VCS 0.0.1-dev',10,0
usage_text: db 'Invalid command or arguments. Run vcs --help.',10,0
unsupported_text: db 'Repository operation unavailable: UFS integration is not implemented.',10,0
names: db 'help',0,'--help',0,'version',0,'--version',0,'init',0,'status',0,'commit',0,'clone',0,'log',0,0
section .text
; rdi=argc including program name, rsi=argv. rax=status, rdx=static NUL text.
; Caller renders text. argv/strings must be readable; NULL entries rejected.
; Preserves all callee-saved registers. No global mutable state.
global cli_main
cli_main:
    test rdi, rdi
    jle .usage
    test rsi, rsi
    jz .usage
    xor ecx, ecx
.validate:
    cmp qword [rsi+rcx*8], 0
    je .usage
    inc rcx
    cmp rcx, rdi
    jl .validate
    cmp rdi, 1
    je .help
    lea r8, [names]
    xor r9d, r9d
.command:
    mov r10, [rsi+8]
    mov r11, r8
.compare:
    mov al, [r10]
    cmp al, [r11]
    jne .skip
    inc r10
    inc r11
    test al, al
    jnz .compare
    cmp r9d, 4
    jae cli_cmd_commit
    cmp rdi, 2
    jne .usage
    cmp r9d, 2
    jae .version
.help:
    xor eax, eax
    lea rdx, [help_text]
    ret
.version:
    xor eax, eax
    lea rdx, [version_text]
    ret
.skip:
    cmp byte [r8], 0
    lea r8, [r8+1]
    jne .skip
    inc r9d
    cmp byte [r8], 0
    jne .command
.usage:
    mov eax, VCS_ERR_USAGE
    lea rdx, [usage_text]
    ret
; Direct callers must also receive failure until persistent operations exist.
global cli_cmd_clone, cli_cmd_commit
cli_cmd_clone:
cli_cmd_commit:
    mov eax, VCS_ERR_UNSUPPORTED
    lea rdx, [unsupported_text]
    ret
