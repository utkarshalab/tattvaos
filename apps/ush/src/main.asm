; Native Ush entry points. One serialized shell instance, caller-supplied I/O.
%include "inc/ush.inc"
%include "inc/frontend.inc"
bits 64
default rel
extern env_init,cmd_registry_init,commands_init,history_init,history_add
extern parser_tokenize,token_argv,exec_dispatch
extern chain_prepare,chain_entries,line_init,frontend_set_prompt
extern frontend_write_str,frontend_read_line,frontend_shutdown,ush_frontend
section .bss
global ush_last_status,ush_running,ush_exit_requested,ush_interactive
ush_last_status: resq 1
ush_running: resq 1
ush_exit_requested: resq 1
ush_interactive: resq 1
shell_line: resb USH_MAX_LINE_LEN
section .rodata
welcome: db 'Utkarsha Shell 0.1.0-dev | help for commands',10,0
prompt: db 'ush> ',0
syntax_error: db 'ush: syntax error, unsupported operator, or argument/expansion limit',10,0
input_error: db 'ush: input exceeds 4095 bytes or contains NUL',10,0
io_error: db 'ush: frontend read failed',10,0
section .text
global ush_init,ush_execute,ush_main
ush_init:
 test rdi,rdi
 jz .bad
 cmp qword [rdi+io_frontend_t.read_line],0
 je .bad
 mov rax,[rdi+io_frontend_t.write_str]
 or rax,[rdi+io_frontend_t.write]
 jz .bad
 mov [ush_frontend],rdi
 mov rax,[rdi+io_frontend_t.init]
 sub rsp,8
 test rax,rax
 jz .state
 call rax
.state:
 mov qword [ush_last_status],0
 mov qword [ush_running],1
 mov qword [ush_exit_requested],0
 mov qword [ush_interactive],0
 call env_init
 call cmd_registry_init
 call commands_init
 call history_init
 call line_init
 add rsp,8
 xor eax,eax
 ret
.bad:
 mov eax,1
 ret
ush_execute:
 push rbx
 push r12
 push r13
 mov rbx,rdi
 test rdi,rdi
 jz .syntax
 call history_add
 test rax,rax
 js .syntax
 mov rdi,rbx
 call chain_prepare
 test rax,rax
 js .syntax
 jz .blank
 mov r12,rax
 xor r13d,r13d
.command:
 mov rax,r13
 shl rax,4
 lea rdx,[chain_entries]
 mov rcx,[rdx+rax+8]
 cmp rcx,1
 je .and
 cmp rcx,2
 je .or
 jmp .run
.and:
 cmp qword [ush_last_status],0
 jne .next
 jmp .run
.or:
 cmp qword [ush_last_status],0
 je .next
.run:
 mov rdi,[rdx+rax]
 call parser_tokenize
 test rax,rax
 js .syntax
 jz .next
 mov rdi,rax
 lea rsi,[token_argv]
 call exec_dispatch
 mov [ush_last_status],rax
 cmp qword [ush_exit_requested],0
 jne .blank
.next:
 inc r13
 cmp r13,r12
 jb .command
 jmp .blank
.syntax:
 lea rdi,[syntax_error]
 call frontend_write_str
 mov eax,2
.status:
 mov [ush_last_status],rax
 pop r13
 pop r12
 pop rbx
 ret
.blank:
 mov rax,[ush_last_status]
 pop r13
 pop r12
 pop rbx
 ret
; ush_main(rdi=io_frontend_t*, rsi=flags) -> final status; interactive flag bit 0.
ush_main:
 push r12
 mov r12,rsi
 call ush_init
 test eax,eax
 jnz .return
 and r12d,1
 mov [ush_interactive],r12
 test r12,r12
 jz .loop
 lea rdi,[welcome]
 call frontend_write_str
.loop:
 cmp qword [ush_running],0
 je .done
 cmp qword [ush_interactive],0
 je .read
 lea rdi,[prompt]
 mov esi,1
 call frontend_set_prompt
.read:
 lea rdi,[shell_line]
 mov esi,USH_MAX_LINE_LEN
 call frontend_read_line
 cmp rax,-1
 je .done
 cmp rax,-3
 je .io
 cmp rax,-4
 je .cancel
 test rax,rax
 js .long
 lea rdi,[shell_line]
 call ush_execute
 jmp .loop
.cancel:
 mov qword [ush_last_status],130
 jmp .loop
.long:
 lea rdi,[input_error]
 call frontend_write_str
 mov qword [ush_last_status],2
 jmp .loop
.io:
 lea rdi,[io_error]
 call frontend_write_str
 mov qword [ush_last_status],1
.done:
 call frontend_shutdown
 mov rax,[ush_last_status]
.return:
 pop r12
 ret
section .note.GNU-stack noalloc noexec nowrite progbits
