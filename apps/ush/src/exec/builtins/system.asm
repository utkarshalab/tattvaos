; Platform hooks are installed by the native kernel / Linux development runner.
; clock()->nanoseconds since boot or negative; sleep(seconds)->status;
; power(0=shutdown,1=reboot) never returns on success.
bits 64
default rel
extern frontend_write_str,ush_print_number,ush_parse_uint,uxv_sync
section .bss
global ush_clock_hook,ush_sleep_hook,ush_power_hook
ush_clock_hook: resq 1
ush_sleep_hook: resq 1
ush_power_hook: resq 1
section .rodata
clear_text: db 27,'[2J',27,'[H',0
seconds: db ' seconds',10,0
invalid: db 'ush: sleep requires an integer from 0 to 86400 seconds',10,0
unavailable: db 'ush: platform operation unavailable or failed',10,0
flush_error: db 'ush: storage flush failed; power action cancelled',10,0
shutdown_text: db 'Shutting down Utkarsha OS...',10,0
reboot_text: db 'Rebooting Utkarsha OS...',10,0
section .text
global cmd_clear,cmd_uptime,cmd_sleep,cmd_shutdown,cmd_reboot
cmd_clear:
 sub rsp,8
 lea rdi,[clear_text]
 call frontend_write_str
 xor eax,eax
 add rsp,8
 ret
cmd_uptime:
 sub rsp,8
 cmp qword [ush_clock_hook],0
 je platform_error
 call [ush_clock_hook]
 test rax,rax
 js platform_error
 xor edx,edx
 mov ecx,1000000000
 div rcx
 mov rdi,rax
 call ush_print_number
 lea rdi,[seconds]
 call frontend_write_str
 xor eax,eax
 add rsp,8
 ret
cmd_sleep:
 sub rsp,8
 mov rdi,[rsi+8]
 call ush_parse_uint
 test rax,rax
 js .bad
 cmp rax,86400
 ja .bad
 cmp qword [ush_sleep_hook],0
 je platform_error
 mov rdi,rax
 call [ush_sleep_hook]
 test rax,rax
 js platform_error
 xor eax,eax
 add rsp,8
 ret
.bad:
 lea rdi,[invalid]
 call frontend_write_str
 mov eax,2
 add rsp,8
 ret
platform_error:
 lea rdi,[unavailable]
 call frontend_write_str
 mov eax,1
 add rsp,8
 ret
cmd_shutdown:
 xor edx,edx
 jmp power
cmd_reboot:
 mov edx,1
power:
 push rbx
 mov ebx,edx
 cmp qword [ush_power_hook],0
 je .unavailable
 call uxv_sync
 test rax,rax
 js .flush_failed
 lea rdi,[shutdown_text]
 test ebx,ebx
 jz .announce
 lea rdi,[reboot_text]
.announce:
 call frontend_write_str
 mov edi,ebx
 call [ush_power_hook]
.unavailable:
 lea rdi,[unavailable]
 jmp .error
.flush_failed:
 lea rdi,[flush_error]
.error:
 call frontend_write_str
 mov eax,1
 pop rbx
 ret
section .note.GNU-stack noalloc noexec nowrite progbits
