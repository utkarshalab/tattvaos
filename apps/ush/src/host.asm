; Linux development runner. No Linux syscalls are present in the shell core.
%include "inc/frontend.inc"
bits 64
default rel
extern host_disk_open,host_platform_init
extern uedit_active
extern ush_main,ush_init,ush_execute,frontend_shutdown
section .rodata
disk_arg: db '--disk',0
host_name: db 'linux-terminal',0
usage: db 'Usage: ush [--disk IMAGE] [-c "command"]',10,'Run without arguments for a terminal session.',10,0
help_arg: db '--help',0
editor_leave: db 27,'[?25h',27,'[?1049l'
editor_leave_size: equ $-editor_leave
section .data
host_frontend:
 istruc io_frontend_t
 at io_frontend_t.name, dq host_name
 at io_frontend_t.init, dq host_init
 at io_frontend_t.shutdown, dq host_restore
 at io_frontend_t.read_line, dq host_read_line
 at io_frontend_t.write, dq host_write
 at io_frontend_t.get_char, dq host_get_char
 at io_frontend_t.get_size, dq host_get_size
 iend
host_signal_action: dq host_signal,0x04000000,host_sigreturn,0
host_resize_action: dq host_resize,0x04000000,host_sigreturn,0
section .bss
host_resized: resq 1
host_byte: resb 1
terminal_settings: resb 64
raw_settings: resb 64
host_tty: resq 1
host_raw: resq 1
section .text
global _start
_start:
 call host_platform_init
 mov r12,rsp
 cmp qword [r12],3
 jb .arguments
 mov rdi,[r12+16]
 lea rsi,[disk_arg]
.disk_compare:
 mov al,[rdi]
 cmp al,[rsi]
 jne .arguments
 inc rdi
 inc rsi
 test al,al
 jnz .disk_compare
 mov rdi,[r12+24]
 call host_disk_open
 test eax,eax
 jnz .usage
 mov rax,[r12]
 sub rax,2
 add r12,16
 mov [r12],rax
.arguments:
 cmp qword [r12],1
 je .repl
 cmp qword [r12],2
 je .help
 cmp qword [r12],3
 jne .usage
 mov rdi,[r12+16]
 cmp word [rdi],'-c'
 jne .usage
 cmp byte [rdi+2],0
 jne .usage
 lea rdi,[host_frontend]
 call ush_init
 test eax,eax
 jnz .exit_status
 mov rdi,[r12+24]
 call ush_execute
 mov ebx,eax
 call frontend_shutdown
 mov eax,ebx
 jmp .exit_status
.help:
 mov rdi,[r12+16]
 lea rsi,[help_arg]
.compare:
 mov al,[rdi]
 cmp al,[rsi]
 jne .usage
 inc rdi
 inc rsi
 test al,al
 jnz .compare
 xor ebx,ebx
 jmp .show_usage
.usage:
 mov ebx,2
.show_usage:
 lea rdi,[usage]
 xor esi,esi
.length:
 cmp byte [rdi+rsi],0
 je .write_usage
 inc rsi
 jmp .length
.write_usage:
 call host_write
 mov eax,ebx
 jmp .exit_status
.repl:
 ; Query terminal line discipline; piped input receives no banners/prompts.
 mov eax,16
 xor edi,edi
 mov esi,0x5401
 lea rdx,[terminal_settings]
 syscall
 xor esi,esi
 test rax,rax
 setns sil
 mov [host_tty],rsi
 lea rdi,[host_frontend]
 call ush_main
.exit_status:
 mov ebx,eax
 call host_restore
 mov eax,ebx
 mov edi,eax
 mov eax,60
 syscall

host_write:
 mov rdx,rsi
 mov rsi,rdi
 mov edi,1
.loop:
 test rdx,rdx
 jz .done
 mov eax,1
 syscall
 cmp rax,-4
 je .loop
 test rax,rax
 jle .failure
 add rsi,rax
 sub rdx,rax
 jmp .loop
.done: ret
.failure:
 sub rsp,8
 call host_restore
 add rsp,8
 mov edi,1
 mov eax,60
 syscall
host_init:
 cmp qword [host_tty],0
 je .done
 push rbx
 mov ebx,1
.signal:
 mov edi,ebx
 lea rsi,[host_signal_action]
 xor edx,edx
 mov r10d,8
 mov eax,13
 syscall
 test rax,rax
 js .failure
 cmp ebx,1
 jne .second
 mov ebx,2
 jmp .signal
.second:
 cmp ebx,2
 jne .third
 mov ebx,13
 jmp .signal
.third:
 cmp ebx,13
 jne .raw
 mov ebx,15
 jmp .signal
.raw:
 mov edi,28
 lea rsi,[host_resize_action]
 xor edx,edx
 mov r10d,8
 mov eax,13
 syscall
 test rax,rax
 js .failure
 lea rsi,[terminal_settings]
 lea rdi,[raw_settings]
 mov ecx,36
 rep movsb
 and dword [raw_settings],~(1|2|8|32|64|128|256|1024)
 and dword [raw_settings+12],~(1|2|8|0x8000)
 mov byte [raw_settings+22],0
 mov byte [raw_settings+23],1
 mov eax,16
 xor edi,edi
 mov esi,0x5402
 lea rdx,[raw_settings]
 syscall
 test rax,rax
 js .failure
 mov qword [host_raw],1
 pop rbx
.done: ret
.failure:
 mov edi,1
 mov eax,60
 syscall
host_restore:
 cmp qword [uedit_active],0
 je .terminal
 mov qword [uedit_active],0
 mov eax,1
 mov edi,1
 lea rsi,[editor_leave]
 mov edx,editor_leave_size
 syscall
.terminal:
 cmp qword [host_raw],0
 je .done
 mov eax,16
 xor edi,edi
 mov esi,0x5402
 lea rdx,[terminal_settings]
 syscall
 mov qword [host_raw],0
.done: ret
; Existing optional frontend size contract, with 80x24 caller defaults if the
; terminal does not supply a nonzero size. Syscall only; no heap or libc.
host_get_size:
 mov r8,rdi
 mov r9,rsi
 sub rsp,16
 mov eax,16
 xor edi,edi
 mov esi,0x5413
 mov rdx,rsp
 syscall
 test rax,rax
 js .done
 movzx eax,word [rsp+2]
 test eax,eax
 jz .done
 mov [r8],rax
 movzx eax,word [rsp]
 test eax,eax
 jz .done
 mov [r9],rax
.done:
 add rsp,16
 ret
host_signal:
 push rdi
 call host_restore
 pop rdi
 add edi,128
 mov eax,60
 syscall
host_sigreturn:
 mov eax,15
 syscall
host_resize:
 mov qword [host_resized],1
 ret
host_get_char:
.read:
 cmp qword [host_resized],0
 je .byte
 mov qword [host_resized],0
 cmp qword [uedit_active],0
 je .byte
 mov rax,-2
 ret
.byte:
 xor eax,eax
 xor edi,edi
 lea rsi,[host_byte]
 mov edx,1
 syscall
 cmp rax,-4
 je .read
 test rax,rax
 js .error
 jz .eof
 movzx eax,byte [host_byte]
 ret
.error:
 mov rax,-3
 ret
.eof:
 mov rax,-1
 ret
host_read_line:
 push rbx
 push r12
 push r13
 push r14
 push r15
 mov r12,rdi
 mov r13,rsi
 test rsi,rsi
 jz .io
 dec r13
 xor r14d,r14d
 xor r15d,r15d
 mov byte [r12],0
.read:
 xor eax,eax
 xor edi,edi
 lea rsi,[host_byte]
 mov edx,1
 syscall
 cmp rax,-4
 je .read
 test rax,rax
 js .io
 jz .eof
 mov al,[host_byte]
 cmp al,10
 je .end
 test r15d,r15d
 jnz .read
 test al,al
 jz .invalid
 cmp r14,r13
 jae .invalid
 mov [r12+r14],al
 inc r14
 jmp .read
.invalid:
 mov r15d,1
 jmp .read
.eof:
 test r15d,r15d
 jnz .bad
 test r14,r14
 jnz .end
 mov rax,-1
 jmp .return
.end:
 test r15d,r15d
 jnz .bad
 mov byte [r12+r14],0
 mov rax,r14
 jmp .return
.bad:
 mov byte [r12],0
 mov rax,-2
 jmp .return
.io:
 mov rax,-3
.return:
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 ret
section .note.GNU-stack noalloc noexec nowrite progbits
