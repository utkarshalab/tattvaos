; Fixed-capacity owned environment: 32 slots, 63-byte names, 255-byte values.
; No pointers into mutable command input are retained.
bits 64
default rel
extern frontend_write_str
section .bss
env_slots: resb 32*320
section .rodata
env_equals: db '=',0
env_newline: db 10,0
section .text
global env_init,env_set_var,env_get_var,env_unset_var,env_print,ush_streq,env_valid_name
ush_streq:
.loop:
 mov al,[rdi]
 cmp al,[rsi]
 jne .different
 inc rdi
 inc rsi
 test al,al
 jnz .loop
 xor eax,eax
 ret
.different:
 mov eax,1
 ret
; Return eax=0 for valid [A-Za-z_][A-Za-z0-9_]*, 1 otherwise.
env_valid_name:
 test rdi,rdi
 jz .bad
 xor ecx,ecx
.next:
 mov al,[rdi+rcx]
 test al,al
 jz .end
 cmp ecx,63
 jae .bad
 cmp al,'_'
 je .ok
 cmp al,'A'
 jb .number
 cmp al,'Z'
 jbe .ok
 cmp al,'a'
 jb .number
 cmp al,'z'
 jbe .ok
.number:
 test ecx,ecx
 jz .bad
 cmp al,'0'
 jb .bad
 cmp al,'9'
 ja .bad
.ok:
 inc ecx
 jmp .next
.end:
 test ecx,ecx
 jz .bad
 xor eax,eax
 ret
.bad:
 mov eax,1
 ret
env_init:
 lea rdi,[env_slots]
 mov ecx,32*320/8
 xor eax,eax
 rep stosq
 ret
env_get_var:
 push rbx
 push r12
 sub rsp,8
 mov r12,rdi
 lea rbx,[env_slots]
.loop:
 cmp byte [rbx],0
 je .next
 mov rdi,r12
 mov rsi,rbx
 call ush_streq
 test eax,eax
 jz .found
.next:
 add rbx,320
 lea rax,[env_slots+32*320]
 cmp rbx,rax
 jb .loop
 xor eax,eax
 jmp .done
.found:
 lea rax,[rbx+64]
.done:
 add rsp,8
 pop r12
 pop rbx
 ret
env_set_var:
 push rbx
 push rbp
 push r12
 push r13
 push r14
 mov r12,rdi
 mov r13,rsi
 call env_valid_name
 test eax,eax
 jnz .bad
 test r13,r13
 jz .bad
 xor ecx,ecx
.length:
 cmp byte [r13+rcx],0
 je .search
 inc ecx
 cmp ecx,256
 jb .length
 jmp .bad
.search:
 xor ebp,ebp
 lea rbx,[env_slots]
.loop:
 cmp byte [rbx],0
 jne .compare
 test rbp,rbp
 cmovz rbp,rbx
 jmp .next
.compare:
 mov rdi,r12
 mov rsi,rbx
 call ush_streq
 test eax,eax
 jz .store
.next:
 add rbx,320
 lea rax,[env_slots+32*320]
 cmp rbx,rax
 jb .loop
 test rbp,rbp
 jz .bad
 mov rbx,rbp
.store:
 mov rdi,rbx
 mov rsi,r12
.copy_key:
 lodsb
 stosb
 test al,al
 jnz .copy_key
 lea rdi,[rbx+64]
 mov rsi,r13
.copy_value:
 lodsb
 stosb
 test al,al
 jnz .copy_value
 xor eax,eax
 jmp .done
.bad:
 mov eax,1
.done:
 pop r14
 pop r13
 pop r12
 pop rbp
 pop rbx
 ret
env_unset_var:
 sub rsp,8
 call env_get_var
 add rsp,8
 test rax,rax
 jz .done
 mov byte [rax-64],0
.done:
 xor eax,eax
 ret
env_print:
 push rbx
 lea rbx,[env_slots]
.loop:
 cmp byte [rbx],0
 je .next
 mov rdi,rbx
 call frontend_write_str
 lea rdi,[env_equals]
 call frontend_write_str
 lea rdi,[rbx+64]
 call frontend_write_str
 lea rdi,[env_newline]
 call frontend_write_str
.next:
 add rbx,320
 lea rax,[env_slots+32*320]
 cmp rbx,rax
 jb .loop
 xor eax,eax
 pop rbx
 ret
section .note.GNU-stack noalloc noexec nowrite progbits
