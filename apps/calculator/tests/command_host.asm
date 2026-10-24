; Host harness for the native command: stdout callback replaces shell frontend.
bits 64
default rel
extern cmd_calc
section .text
global _start, frontend_write_str
_start:
 mov rdi,[rsp]
 lea rsi,[rsp+8]
 call cmd_calc
 mov edi,eax
 mov eax,60
 syscall
frontend_write_str:
 mov rsi,rdi
 xor edx,edx
.length:
 cmp byte [rsi+rdx],0
 je .write
 inc rdx
 jmp .length
.write:
 mov edi,1
 mov eax,1
 syscall
 ret
section .note.GNU-stack noalloc noexec nowrite progbits
