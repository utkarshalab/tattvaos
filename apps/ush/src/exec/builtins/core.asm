; Working builtins; filesystem commands use the persistent UXFS volume.
%include "inc/cmd_registry.inc"
%include "apps/calculator/src/session.inc"
bits 64
default rel
extern frontend_write_str,frontend_read_line,ush_streq,cmd_registry_root
extern uxv_mount
extern frontend_set_prompt
extern ush_last_status,ush_running,ush_exit_requested,ush_interactive
extern env_print,env_set_var,env_unset_var,env_valid_name,history_print,history_init
extern calc_format,calc_cli,calc_session,calc_session_init
section .rodata
newline: db 10,0
space: db ' ',0
separator: db ' - ',0
dash_n: db '-n',0
dash_c: db '-c',0
version_text: db 'Utkarsha Shell 0.1.0-dev',10,0
usage_error: db 'ush: invalid arguments or environment capacity exceeded',10,0
calc_banner: db 'Calculator: help for functions; quit returns to Ush.',10,0
calc_prompt: db 'calc> ',0
calc_line_error: db 'calc: input exceeds 255 bytes or contains NUL',10,0
section .bss
number: resb 67
calculator_context: resb CALC_CONTEXT_SIZE
calculator_output: resb CALC_OUTPUT_SIZE
calculator_line: resb CALC_LINE_SIZE
section .text
global commands_init,cmd_echo,cmd_help,cmd_exit,cmd_true,cmd_false,cmd_status
 global cmd_env,cmd_export,cmd_unset,cmd_history,cmd_calc,cmd_version
commands_init:
 sub rsp,8
 call uxv_mount
 lea rdi,[calculator_context]
 call calc_session_init
 add rsp,8
 ret
builtin_usage:
 sub rsp,8
 lea rdi,[usage_error]
 call frontend_write_str
 add rsp,8
 mov eax,2
 ret
cmd_echo:
 push rbx
 push r12
 push r13
 push r14
 sub rsp,8
 mov r12,rdi
 mov r13,rsi
 mov ebx,1
 xor r14d,r14d
 cmp r12,2
 jb .loop
 mov rdi,[r13+8]
 lea rsi,[dash_n]
 call ush_streq
 test eax,eax
 jnz .loop
 inc ebx
 mov r14d,1
.loop:
 cmp rbx,r12
 jae .newline
 mov rdi,[r13+rbx*8]
 call frontend_write_str
 inc rbx
 cmp rbx,r12
 jae .newline
 lea rdi,[space]
 call frontend_write_str
 jmp .loop
.newline:
 test r14d,r14d
 jnz .done
 lea rdi,[newline]
 call frontend_write_str
.done:
 xor eax,eax
 add rsp,8
 pop r14
 pop r13
 pop r12
 pop rbx
 ret
cmd_help:
 push rbx
 mov rbx,[cmd_registry_root]
.loop:
 test rbx,rbx
 jz .done
 mov rdi,[rbx+cmd_entry_t.name]
 call frontend_write_str
 lea rdi,[separator]
 call frontend_write_str
 mov rdi,[rbx+cmd_entry_t.help]
 call frontend_write_str
 lea rdi,[newline]
 call frontend_write_str
 mov rbx,[rbx+cmd_entry_t.next]
 jmp .loop
.done:
 xor eax,eax
 pop rbx
 ret
cmd_true:
 xor eax,eax
 ret
cmd_false:
 mov eax,1
 ret
cmd_version:
 sub rsp,8
 lea rdi,[version_text]
 call frontend_write_str
 add rsp,8
 xor eax,eax
 ret
cmd_status:
 sub rsp,8
 mov rdi,[ush_last_status]
 mov esi,10
 lea rdx,[number]
 call calc_format
 lea rdi,[number]
 call frontend_write_str
 lea rdi,[newline]
 call frontend_write_str
 add rsp,8
 xor eax,eax
 ret
cmd_exit:
 mov eax,[ush_last_status]
 cmp rdi,1
 je .exit
 mov rsi,[rsi+8]
 xor eax,eax
 xor ecx,ecx
.parse:
 movzx edx,byte [rsi]
 test edx,edx
 jz .end
 sub edx,'0'
 cmp edx,9
 ja builtin_usage
 imul eax,eax,10
 add eax,edx
 cmp eax,255
 ja builtin_usage
 inc rsi
 inc ecx
 jmp .parse
.end:
 test ecx,ecx
 jz builtin_usage
.exit:
 mov qword [ush_running],0
 mov qword [ush_exit_requested],1
 ret
cmd_env:
 jmp env_print
cmd_export:
 cmp rdi,1
 je env_print
 push rbx
 push r12
 push r13
 push r14
 sub rsp,8
 mov r12,rdi
 mov r14,rsi
 mov ebx,1
.loop:
 mov rdi,[r14+rbx*8]
 mov r13,rdi
.find_equal:
 cmp byte [r13],0
 je .bad
 cmp byte [r13],'='
 je .set
 inc r13
 jmp .find_equal
.set:
 mov byte [r13],0
 lea rsi,[r13+1]
 call env_set_var
 mov byte [r13],'='
 test eax,eax
 jnz .bad
 inc rbx
 cmp rbx,r12
 jb .loop
 xor eax,eax
 jmp .done
.bad:
 call builtin_usage
.done:
 add rsp,8
 pop r14
 pop r13
 pop r12
 pop rbx
 ret
cmd_unset:
 push rbx
 push r12
 push r13
 mov r12,rdi
 mov r13,rsi
 mov ebx,1
.loop:
 mov rdi,[r13+rbx*8]
 call env_valid_name
 test eax,eax
 jnz .bad
 mov rdi,[r13+rbx*8]
 call env_unset_var
 inc rbx
 cmp rbx,r12
 jb .loop
 xor eax,eax
 jmp .done
.bad:
 call builtin_usage
.done:
 pop r13
 pop r12
 pop rbx
 ret
cmd_history:
 cmp rdi,1
 je history_print
 sub rsp,8
 mov rdi,[rsi+8]
 lea rsi,[dash_c]
 call ush_streq
 add rsp,8
 test eax,eax
 jnz builtin_usage
 jmp history_init
cmd_calc:
 push rbx
 cmp rdi,1
 je .interactive
 lea rdx,[calculator_context]
 lea rcx,[calculator_output]
 call calc_cli
 mov ebx,eax
 lea rdi,[calculator_output]
 call frontend_write_str
 cmp ebx,255
 jne .return
 xor ebx,ebx
.return:
 mov eax,ebx
 pop rbx
 ret
.interactive:
 cmp qword [ush_interactive],0
 je .loop
 lea rdi,[calc_banner]
 call frontend_write_str
.loop:
 cmp qword [ush_interactive],0
 je .read
 lea rdi,[calc_prompt]
 xor esi,esi
 call frontend_set_prompt
.read:
 lea rdi,[calculator_line]
 mov esi,CALC_LINE_SIZE
 call frontend_read_line
 cmp rax,-1
 je .success
 cmp rax,-3
 je .io_error
 cmp rax,-4
 je .loop
 test rax,rax
 js .long
 lea rdi,[calculator_context]
 lea rsi,[calculator_line]
 lea rdx,[calculator_output]
 call calc_session
 mov ebx,eax
 lea rdi,[calculator_output]
 call frontend_write_str
 cmp ebx,255
 je .success
 jmp .loop
.long:
 lea rdi,[calc_line_error]
 call frontend_write_str
 jmp .loop
.io_error:
 mov ebx,1
 jmp .return
.success:
 xor ebx,ebx
 jmp .return
section .note.GNU-stack noalloc noexec nowrite progbits
