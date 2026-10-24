; Linked command registry with bounded, ABI-correct dispatch.
%include "inc/cmd_registry.inc"
bits 64
default rel
extern ush_streq,frontend_write_str
section .bss
global cmd_registry_root
cmd_registry_root: resq 1
section .rodata
unknown: db 'ush: command not found',10,0
bad_args: db 'ush: invalid argument count',10,0
unavailable: db 'ush: command handler unavailable',10,0
section .text
global exec_register_command,exec_lookup,exec_dispatch
exec_register_command:
 mov rax,[cmd_registry_root]
 mov [rdi+cmd_entry_t.next],rax
 mov [cmd_registry_root],rdi
 ret
exec_lookup:
 push rbx
 push r12
 sub rsp,8
 mov r12,rdi
 mov rbx,[cmd_registry_root]
.loop:
 test rbx,rbx
 jz .done
 mov rdi,r12
 mov rsi,[rbx+cmd_entry_t.name]
 call ush_streq
 test eax,eax
 jz .done
 mov rbx,[rbx+cmd_entry_t.next]
 jmp .loop
.done:
 mov rax,rbx
 add rsp,8
 pop r12
 pop rbx
 ret
exec_dispatch:
 push rbx
 push r12
 sub rsp,8
 mov rbx,rdi
 mov r12,rsi
 test rdi,rdi
 jz .empty
 test rsi,rsi
 jz .usage
 mov rdi,[rsi]
 test rdi,rdi
 jz .usage
 call exec_lookup
 test rax,rax
 jz .unknown
 cmp ebx,[rax+cmd_entry_t.min_args]
 jb .usage
 cmp ebx,[rax+cmd_entry_t.max_args]
 ja .usage
 mov rax,[rax+cmd_entry_t.handler]
 test rax,rax
 jz .missing
 mov rdi,rbx
 mov rsi,r12
 call rax
 jmp .return
.empty:
 xor eax,eax
 jmp .return
.unknown:
 lea rdi,[unknown]
 call frontend_write_str
 mov eax,127
 jmp .return
.usage:
 lea rdi,[bad_args]
 call frontend_write_str
 mov eax,2
 jmp .return
.missing:
 lea rdi,[unavailable]
 call frontend_write_str
 mov eax,126
.return:
 add rsp,8
 pop r12
 pop rbx
 ret
section .note.GNU-stack noalloc noexec nowrite progbits
