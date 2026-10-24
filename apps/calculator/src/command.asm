; Native shell command. No OS calls; transient one-shot session on caller stack.
%include "src/session.inc"
bits 64
default rel
extern calc_session_init,calc_cli,frontend_write_str
section .text
global cmd_calc
cmd_calc:
 push rbx
 push r12
 push r13
 sub rsp,CALC_CONTEXT_SIZE+CALC_OUTPUT_SIZE
 mov r12,rdi
 mov r13,rsi
 mov rdi,rsp
 call calc_session_init
 mov rdi,r12
 mov rsi,r13
 mov rdx,rsp
 lea rcx,[rsp+CALC_CONTEXT_SIZE]
 call calc_cli
 mov ebx,eax
 lea rdi,[rsp+CALC_CONTEXT_SIZE]
 call frontend_write_str
 mov eax,ebx
 add rsp,CALC_CONTEXT_SIZE+CALC_OUTPUT_SIZE
 pop r13
 pop r12
 pop rbx
 ret
section .note.GNU-stack noalloc noexec nowrite progbits
