; Shared command-line adapter: initialized caller context, caller output buffer.
; calc_cli(argc:rdi, argv:rsi, context:rdx, output:rcx) -> eax=status.
; Scientific by default. -d/-x/-b select exact programmer arithmetic.
%include "src/session.inc"
bits 64
default rel
extern calc_session
section .rodata
cli_usage: db 'Usage: calc [--science|--programmer|--deg|-d|-x|-b] "expression"',10
 db '       calc               Interactive session',10
 db '       calc --help        Functions and session commands',10,0
cli_help: db '--help',0
cli_help_line: db 'help',0
cli_sci: db '--science',0
cli_prog: db '--programmer',0
cli_deg: db '--deg',0
cli_dec: db '-d',0
cli_hex: db '-x',0
cli_bin: db '-b',0
section .text
global calc_cli
calc_cli:
 push rbx
 push r12
 push r13
 push r14
 push r15
 mov r12,rdx
 mov r13,rcx
 mov r14,rsi
 mov r15,rdi
 test rsi,rsi
 jz .usage
 cmp rdi,2
 je .expression
 cmp rdi,3
 jne .usage
 mov rbx,[r14+8]
 test rbx,rbx
 jz .usage
 lea rsi,[cli_sci]
 call .equal
 jz .science
 lea rsi,[cli_prog]
 call .equal
 jz .programmer
 lea rsi,[cli_deg]
 call .equal
 jz .degrees
 lea rsi,[cli_dec]
 call .equal
 jz .decimal
 lea rsi,[cli_hex]
 call .equal
 jz .hexadecimal
 lea rsi,[cli_bin]
 call .equal
 jnz .usage
 mov qword [r12+CALC_BASE],2
 jmp .programmer
.hexadecimal:
 mov qword [r12+CALC_BASE],16
 jmp .programmer
.decimal:
 mov qword [r12+CALC_BASE],10
.programmer:
 mov qword [r12+CALC_MODE],1
 jmp .expression
.science:
 mov qword [r12+CALC_MODE],0
 jmp .expression
.degrees:
 mov qword [r12+CALC_DEGREES],1
.expression:
 mov rsi,[r14+r15*8-8]
 test rsi,rsi
 jz .usage
 cmp r15,2
 jne .session
 mov rbx,rsi
 lea rsi,[cli_dec]
 call .equal
 jz .usage
 lea rsi,[cli_hex]
 call .equal
 jz .usage
 lea rsi,[cli_bin]
 call .equal
 jz .usage
 lea rsi,[cli_help]
 call .equal
 mov rsi,rbx
 jnz .session
 lea rsi,[cli_help_line]
.session:
 mov rdi,r12
 mov rdx,r13
 call calc_session
 test eax,eax
 jnz .return
 cmp byte [r13],0
 je .usage
 jmp .return
.usage:
 lea rsi,[cli_usage]
 mov rdi,r13
.copy:
 lodsb
 stosb
 test al,al
 jnz .copy
 mov eax,1
.return:
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 ret
.equal:
 mov rdi,rbx
.loop:
 mov al,[rdi]
 cmp al,[rsi]
 jne .done
 inc rdi
 inc rsi
 test al,al
 jnz .loop
.done: ret
section .note.GNU-stack noalloc noexec nowrite progbits
