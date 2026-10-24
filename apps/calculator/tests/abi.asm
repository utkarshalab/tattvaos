; Test System V preservation across representative scientific/session calls.
%include "src/session.inc"
bits 64
default rel
extern calc_session_init,calc_session
section .rodata
abi_line: db 'pow(2,3) + sin(pi/2)',0
section .bss
abi_context: resb CALC_CONTEXT_SIZE
abi_output: resb CALC_OUTPUT_SIZE
section .text
global _start
_start:
 lea rdi,[abi_context]
 call calc_session_init
 mov rbx,101
 mov rbp,202
 mov r12,303
 mov r13,404
 mov r14,505
 mov r15,606
 lea rdi,[abi_context]
 lea rsi,[abi_line]
 lea rdx,[abi_output]
 call calc_session
 test eax,eax
 jnz .fail
 cmp rbx,101
 jne .fail
 cmp rbp,202
 jne .fail
 cmp r12,303
 jne .fail
 cmp r13,404
 jne .fail
 cmp r14,505
 jne .fail
 cmp r15,606
 jne .fail
 cmp word [rel abi_output],0x0a39 ; 9 + newline
 jne .fail
 xor edi,edi
 jmp .exit
.fail:
 mov edi,1
.exit:
 mov eax,60
 syscall
section .note.GNU-stack noalloc noexec nowrite progbits
