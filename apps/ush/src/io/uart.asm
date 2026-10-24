; Native COM1 frontend. Privileged instructions: native kernel use only.
%include "inc/frontend.inc"
bits 64
default rel
extern uxv_ata_init
section .rodata
uart_name: db 'uart0',0
section .data
global uart_frontend
uart_frontend:
 istruc io_frontend_t
 at io_frontend_t.name, dq uart_name
 at io_frontend_t.init, dq uart_init
 at io_frontend_t.read_line, dq uart_read_line
 at io_frontend_t.write, dq uart_write
 at io_frontend_t.get_char, dq uart_read_char
 iend
section .bss
align 8
; Optional native scheduler callback. Zero keeps standalone polling behavior.
global uart_idle_hook
uart_idle_hook: resq 1
section .text
uart_init:
 sub rsp,8
 call uxv_ata_init
 add rsp,8
 mov dx,0x3f9
 xor al,al
 out dx,al
 mov dx,0x3fb
 mov al,0x80
 out dx,al
 mov dx,0x3f8
 mov al,1
 out dx,al
 mov dx,0x3f9
 xor al,al
 out dx,al
 mov dx,0x3fb
 mov al,3
 out dx,al
 mov dx,0x3fa
 mov al,0xc7
 out dx,al
 mov dx,0x3fc
 mov al,0x0b
 out dx,al
 ret
uart_put:
 mov cl,al
 mov dx,0x3fd
.wait:
 in al,dx
 test al,0x20
 jz .wait
 mov dx,0x3f8
 mov al,cl
 out dx,al
 ret
uart_get:
 sub rsp,8
.wait:
 mov dx,0x3fd
 in al,dx
 test al,1
 jnz .ready
 mov rax,[uart_idle_hook]
 test rax,rax
 jz .wait
 call rax
 jmp .wait
.ready:
 mov dx,0x3f8
 in al,dx
 add rsp,8
 ret
uart_read_char:
 sub rsp,8
 call uart_get
 movzx eax,al
 add rsp,8
 ret
uart_write:
 push rbx
 push r12
 push r13
 mov r12,rdi
 mov r13,rsi
 xor ebx,ebx
.loop:
 cmp rbx,r13
 jae .done
 mov al,[r12+rbx]
 cmp al,10
 jne .put
 mov al,13
 call uart_put
 mov al,10
.put:
 call uart_put
 inc rbx
 jmp .loop
.done:
 pop r13
 pop r12
 pop rbx
 ret
uart_read_line:
 push rbx
 push r12
 push r13
 push r14
 push r15
 mov r12,rdi
 mov r13,rsi
 test r13,r13
 jz .invalid
 dec r13
 xor r14d,r14d
 xor r15d,r15d
.read:
 call uart_get
 cmp al,4
 je .eof
 cmp al,13
 je .end
 cmp al,10
 je .end
 test r15d,r15d
 jnz .read
 cmp al,8
 je .backspace
 cmp al,127
 je .backspace
 test al,al
 jz .overflow
 cmp r14,r13
 jae .overflow
 mov [r12+r14],al
 inc r14
 call uart_put
 jmp .read
.overflow:
 mov r15d,1
 jmp .read
.backspace:
 test r14,r14
 jz .read
 dec r14
 mov al,8
 call uart_put
 mov al,32
 call uart_put
 mov al,8
 call uart_put
 jmp .read
.eof:
 test r14,r14
 jnz .end
 test r15d,r15d
 jnz .end
 mov byte [r12],0
 mov rax,-1
 jmp .done
.end:
 mov al,13
 call uart_put
 mov al,10
 call uart_put
 mov byte [r12+r14],0
 test r15d,r15d
 jnz .invalid
 mov rax,r14
 jmp .done
.invalid:
 mov rax,-2
.done:
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 ret
section .note.GNU-stack noalloc noexec nowrite progbits
