; Native hook ABI and flush-before-power checks. No real power instructions.
%include "inc/frontend.inc"
bits 64
default rel
extern ush_init,ush_execute,ush_streq,ush_clock_hook,ush_sleep_hook,ush_power_hook
extern uxv_flush,uxv_ready
section .rodata
sleep_cmd: db 'sleep 2',0
bad_sleep: db 'sleep -1',0
uptime_cmd: db 'uptime',0
uptime_expected: db '12 seconds',10,0
shutdown_cmd: db 'shutdown',0
reboot_cmd: db 'reboot',0
section .data
frontend:
 istruc io_frontend_t
 at io_frontend_t.read_line, dq read_line
 at io_frontend_t.write, dq write
 iend
section .bss
capture: resb 4096
length: resq 1
failed: resq 1
sleeps: resq 1
flushes: resq 1
powers: resq 1
flush_failure: resq 1
last_action: resq 1
sequence: resq 1
last_flush: resq 1
section .text
global _start
_start:
 lea rdi,[frontend]
 call ush_init
 test eax,eax
 jnz fail
 lea rax,[clock]
 mov [ush_clock_hook],rax
 lea rax,[sleep]
 mov [ush_sleep_hook],rax
 lea rax,[power]
 mov [ush_power_hook],rax
 lea rdi,[sleep_cmd]
 call ush_execute
 test eax,eax
 jnz fail
 cmp qword [sleeps],1
 jne fail
 lea rdi,[bad_sleep]
 call ush_execute
 cmp eax,2
 jne fail
 cmp qword [sleeps],1
 jne fail
 mov qword [length],0
 lea rdi,[uptime_cmd]
 call ush_execute
 test eax,eax
 jnz fail
 lea rdi,[capture]
 lea rsi,[uptime_expected]
 call ush_streq
 test eax,eax
 jnz fail
 lea rax,[flush]
 mov [uxv_flush],rax
 mov qword [uxv_ready],1
 mov qword [flush_failure],1
 lea rdi,[shutdown_cmd]
 call ush_execute
 cmp eax,1
 jne fail
 cmp qword [powers],0
 jne fail
 cmp qword [flushes],1
 jne fail
 cmp qword [uxv_ready],0
 jne fail
 mov qword [flush_failure],0
 lea rdi,[shutdown_cmd]
 call ush_execute
 cmp eax,1                 ; returning platform hook is reported as failure
 jne fail
 cmp qword [powers],1
 jne fail
 cmp qword [last_action],0
 jne fail
 lea rdi,[reboot_cmd]
 call ush_execute
 cmp eax,1
 jne fail
 cmp qword [powers],2
 jne fail
 cmp qword [last_action],1
 jne fail
 cmp qword [flushes],3
 jne fail
 cmp qword [failed],0
 jne fail
 xor edi,edi
 jmp exit
fail: mov edi,1
exit: mov eax,60
 syscall
clock:
 mov rax,12345000000
 ret
sleep:
 cmp rdi,2
 jne .bad
 inc qword [sleeps]
 mov rax,rsp
 and eax,15
 cmp eax,8
 jne .bad
 xor eax,eax
 ret
.bad:
 mov qword [failed],1
 mov rax,-1
 ret
flush:
 inc qword [flushes]
 inc qword [sequence]
 mov rax,[sequence]
 mov [last_flush],rax
 cmp qword [flush_failure],0
 jne .bad
 xor eax,eax
 ret
.bad: mov rax,-5
 ret
power:
 mov [last_action],rdi
 inc qword [powers]
 inc qword [sequence]
 mov rax,[last_flush]
 inc rax
 cmp rax,[sequence]
 jne .bad
 mov rax,rsp
 and eax,15
 cmp eax,8
 je .done
.bad: mov qword [failed],1
.done: mov rax,-1
 ret
read_line: mov rax,-1
 ret
write:
 mov rcx,rsi
 mov rsi,rdi
 mov rdx,[length]
 add [length],rcx
 cmp qword [length],4095
 ja fail
 lea rdi,[capture+rdx]
 rep movsb
 mov byte [rdi],0
 ret
section .note.GNU-stack noalloc noexec nowrite progbits
