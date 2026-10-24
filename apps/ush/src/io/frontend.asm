; Frontend calls use implicit active frontend, matching command callbacks.
; Vtable read_line(buf,capacity)-> length, -1 EOF, -2 bad line, -3 I/O failure.
%include "inc/frontend.inc"
bits 64
default rel
extern ush_interactive,line_readline
section .bss
global ush_frontend
ush_frontend: resq 1
section .text
global frontend_write_str,frontend_write,frontend_read_line,frontend_shutdown,frontend_get_char
frontend_write_str:
 mov rax,[ush_frontend]
 test rax,rax
 jz .done
 mov rcx,[rax+io_frontend_t.write_str]
 test rcx,rcx
 jnz .direct
 mov rcx,[rax+io_frontend_t.write]
 test rcx,rcx
 jz .done
 xor esi,esi
.length:
 cmp byte [rdi+rsi],0
 je .direct
 inc rsi
 jmp .length
.direct:
 jmp rcx
.done: ret
frontend_write:
 mov rax,[ush_frontend]
 test rax,rax
 jz .done
 mov rax,[rax+io_frontend_t.write]
 test rax,rax
 jz .done
 jmp rax
.done: ret
frontend_read_line:
 mov rax,[ush_frontend]
 test rax,rax
 jz .missing
 cmp qword [ush_interactive],0
 je .plain
 cmp qword [rax+io_frontend_t.get_char],0
 jne line_readline
.plain:
 mov rax,[rax+io_frontend_t.read_line]
 test rax,rax
 jz .missing
 jmp rax
.missing:
 mov rax,-3
 ret
frontend_get_char:
 mov rax,[ush_frontend]
 mov rax,[rax+io_frontend_t.get_char]
 jmp rax
frontend_shutdown:
 mov rax,[ush_frontend]
 test rax,rax
 jz .done
 mov rax,[rax+io_frontend_t.shutdown]
 test rax,rax
 jz .done
 jmp rax
.done: ret
section .note.GNU-stack noalloc noexec nowrite progbits
