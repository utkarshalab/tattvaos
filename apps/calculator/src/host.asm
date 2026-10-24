; Linux development terminal. All host syscalls are confined to this file.
%include "src/session.inc"
bits 64
default rel
extern calc_session_init,calc_session,calc_cli
section .rodata
banner: db 'Utkarsha Calculator | scientific + programmer | help for commands',10,0
prompt: db 'calc> ',0
long_line: db 'calc: input exceeds 255 bytes',10,0
io_error: db 'calc: terminal I/O failed',10,0
section .bss
context: resb CALC_CONTEXT_SIZE
output: resb CALC_OUTPUT_SIZE
line: resb CALC_LINE_SIZE
input_byte: resb 1
section .text
global _start
_start:
 mov r14,rsp
 lea rdi,[context]
 call calc_session_init
 cmp qword [r14],1
 je .interactive
 mov rdi,[r14]
 lea rsi,[r14+8]
 lea rdx,[context]
 lea rcx,[output]
 call calc_cli
 mov r12d,eax
 mov edi,1
 test eax,eax
 jz .one_shot
 mov edi,2
.one_shot:
 lea rsi,[output]
 call write_string
 cmp r12d,255
 jne .exit_status
 xor r12d,r12d
.exit_status:
 mov edi,r12d
 jmp exit_process
.interactive:
 mov edi,1
 lea rsi,[banner]
 call write_string
.next_line:
 mov edi,1
 lea rsi,[prompt]
 call write_string
 xor ebx,ebx
 xor r15d,r15d ; overlong line flag
.read:
 xor eax,eax
 xor edi,edi
 lea rsi,[input_byte]
 mov edx,1
 syscall
 cmp rax,-4
 je .read
 test rax,rax
 js .read_error
 jz .eof
 mov al,[input_byte]
 cmp al,10
 je .line_end
 test r15d,r15d
 jnz .read
 cmp ebx,CALC_LINE_SIZE-1
 jae .overlong
 test al,al
 jz .overlong ; embedded NUL is rejected, never silently truncate
 lea rdx,[line]
 mov [rdx+rbx],al
 inc ebx
 jmp .read
.overlong:
 mov r15d,1
 jmp .read
.line_end:
 test r15d,r15d
 jnz .line_error
 call evaluate_line
 cmp eax,255
 je .exit_ok
 jmp .next_line
.line_error:
 mov edi,2
 lea rsi,[long_line]
 call write_string
 jmp .next_line
.eof:
 test r15d,r15d
 jnz .eof_error
 test ebx,ebx
 jz .exit_ok
 call evaluate_line
 cmp eax,255
 je .exit_ok
 mov edi,eax
 jmp exit_process
.eof_error:
 mov edi,2
 lea rsi,[long_line]
 call write_string
 mov edi,1
 jmp exit_process
.read_error:
 mov edi,2
 lea rsi,[io_error]
 call write_string
 mov edi,6
 jmp exit_process
.exit_ok:
 xor edi,edi
 jmp exit_process

evaluate_line:
 push r12
 lea rsi,[line]
 mov byte [rsi+rbx],0
 lea rdi,[context]
 lea rdx,[output]
 call calc_session
 mov r12d,eax
 mov edi,1
 test eax,eax
 jz .print
 cmp eax,255
 je .print
 mov edi,2
.print:
 lea rsi,[output]
 call write_string
 mov eax,r12d
 pop r12
 ret
write_string:
 xor edx,edx
.length:
 cmp byte [rsi+rdx],0
 je .write
 inc rdx
 jmp .length
.write:
 test rdx,rdx
 jz .done
 mov eax,1
 syscall
 cmp rax,-4
 je .write
 test rax,rax
 jle .failure
 add rsi,rax
 sub rdx,rax
 jmp .write
.done: ret
.failure:
 mov edi,6
exit_process:
 mov eax,60
 syscall
section .note.GNU-stack noalloc noexec nowrite progbits
