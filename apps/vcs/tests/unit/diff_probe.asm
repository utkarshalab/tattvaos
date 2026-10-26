; Host-test adapter only: capture rdx and verify every callee-saved register.
bits 64
default rel
extern diff_files
global diff_probe
section .text
diff_probe:
 push rbp
 push rbx
 push r12
 push r13
 push r14
 push r15
 sub rsp,24
 mov [rsp],rsi
 mov ebp,0x12345678
 mov ebx,0x23456789
 mov r12d,0x3456789a
 mov r13d,0x456789ab
 mov r14d,0x56789abc
 mov r15d,0x6789abcd
 call diff_files
 mov rsi,[rsp]
 mov [rsi],rdx
 cmp rbp,0x12345678
 jne .bad
 cmp rbx,0x23456789
 jne .bad
 cmp r12,0x3456789a
 jne .bad
 cmp r13,0x456789ab
 jne .bad
 cmp r14,0x56789abc
 jne .bad
 cmp r15,0x6789abcd
 jne .bad
 jmp .done
.bad:
 mov eax,999
.done:
 add rsp,24
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 pop rbp
 ret
section .note.GNU-stack noalloc noexec nowrite progbits
