; Linux-only time backend. Deliberately installs NO workstation power control.
bits 64
default rel
extern ush_clock_hook,ush_sleep_hook
section .text
global host_platform_init
host_platform_init:
 lea rax,[clock]
 mov [ush_clock_hook],rax
 lea rax,[sleep]
 mov [ush_sleep_hook],rax
 ret
clock:
 sub rsp,24
 mov edi,7                       ; CLOCK_BOOTTIME
 mov rsi,rsp
 mov eax,228
 syscall
 test rax,rax
 js .done
 mov rax,[rsp]
 imul rax,rax,1000000000
 add rax,[rsp+8]
.done:
 add rsp,24
 ret
sleep:
 sub rsp,40
 mov [rsp],rdi
 mov qword [rsp+8],0
.retry:
 mov rdi,rsp
 lea rsi,[rsp+16]
 mov eax,35                      ; nanosleep
 syscall
 cmp rax,-4
 jne .done
 mov rax,[rsp+16]
 mov [rsp],rax
 mov rax,[rsp+24]
 mov [rsp+8],rax
 jmp .retry
.done:
 add rsp,40
 ret
section .note.GNU-stack noalloc noexec nowrite progbits
