; Exercise native ush_main with memory-only frontend and ABI sentinels.
%include "inc/frontend.inc"
bits 64
default rel
extern ush_main,ush_init,ush_streq,line_log_begin,line_log_end,frontend_write_str
section .rodata
line0: db 'echo "native quote"',0
line1: db 'export V=owned',0
line2: db 'echo "$V"',0
line3: db 'calc "sqrt(81)"',0
line4: db 'exit 7',0
expected: db 'native quote',10,'owned',10,'9',10,0
keys: db 'echo ac',27,'[D','b',13,'exit 0',13
keys_end:
background: db 'BACKGROUND',10,0
restored: db 'BACKGROUND',10,13,27,'[2Kush> echo ac',27,'[1D',0
edited_result: db 10,'abc',10,0
section .data
lines: dq line0,line1,line2,line3,line4
fake_frontend:
 istruc io_frontend_t
 at io_frontend_t.init, dq fake_init
 at io_frontend_t.shutdown, dq fake_shutdown
 at io_frontend_t.read_line, dq fake_read
 at io_frontend_t.write, dq fake_write
 iend
editor_frontend:
 istruc io_frontend_t
 at io_frontend_t.init, dq fake_init
 at io_frontend_t.shutdown, dq fake_shutdown
 at io_frontend_t.read_line, dq fake_read
 at io_frontend_t.write, dq fake_write
 at io_frontend_t.get_char, dq fake_get
 iend
section .bss
captured: resb 8192
captured_len: resq 1
read_index: resq 1
shutdowns: resq 1
failed: resq 1
key_index: resq 1
injected: resq 1
section .text
global _start
_start:
 mov rbx,101
 mov rbp,202
 mov r12,303
 mov r13,404
 mov r14,505
 mov r15,606
 lea rdi,[fake_frontend]
 xor esi,esi
 call ush_main
 cmp eax,7
 jne .fail
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
 cmp qword [failed],0
 jne .fail
 cmp qword [shutdowns],1
 jne .fail
 cmp qword [read_index],5
 jne .fail
 lea rdi,[captured]
 lea rsi,[expected]
 call ush_streq
 test eax,eax
 jnz .fail
 lea rdi,[editor_frontend]
 mov esi,1
 call ush_main
 test eax,eax
 jnz .fail
 cmp qword [failed],0
 jne .fail
 cmp qword [injected],1
 jne .fail
 lea rdi,[captured]
 lea rsi,[restored]
 call contains
 test eax,eax
 jnz .fail
 lea rdi,[captured]
 lea rsi,[edited_result]
 call contains
 test eax,eax
 jnz .fail
 xor edi,edi
 call ush_init
 cmp eax,1
 jne .fail
 xor edi,edi
 jmp .exit
.fail:
 mov edi,1
.exit:
 mov eax,60
 syscall
fake_init:
 mov rax,rsp
 and eax,15
 cmp eax,8
 jne bad_alignment
 mov qword [captured_len],0
 mov qword [read_index],0
 mov qword [key_index],0
 mov qword [injected],0
 ret
fake_get:
 push rbx
 cmp qword [key_index],10
 jne .key
 cmp qword [injected],0
 jne .key
 call line_log_begin
 lea rdi,[background]
 call frontend_write_str
 call line_log_end
 mov qword [injected],1
.key:
 mov rbx,[key_index]
 cmp rbx,keys_end-keys
 jae .eof
 lea rax,[keys]
 movzx eax,byte [rax+rbx]
 inc qword [key_index]
 pop rbx
 ret
.eof:
 mov rax,-1
 pop rbx
 ret
contains:
.start:
 cmp byte [rdi],0
 je .missing
 mov r8,rdi
 mov r9,rsi
.compare:
 mov al,[r9]
 test al,al
 jz .found
 cmp al,[r8]
 jne .next
 inc r8
 inc r9
 jmp .compare
.next:
 inc rdi
 jmp .start
.found:
 xor eax,eax
 ret
.missing:
 mov eax,1
 ret
fake_shutdown:
 mov rax,rsp
 and eax,15
 cmp eax,8
 jne bad_alignment
 inc qword [shutdowns]
 ret
fake_read:
 mov rax,rsp
 and eax,15
 cmp eax,8
 jne bad_read
 mov rcx,[read_index]
 cmp rcx,5
 jae .eof
 lea rdx,[lines]
 mov r8,[rdx+rcx*8]
 inc qword [read_index]
 xor ecx,ecx
.copy:
 cmp rcx,rsi
 jae bad_read
 mov al,[r8+rcx]
 mov [rdi+rcx],al
 test al,al
 jz .done
 inc rcx
 jmp .copy
.done:
 mov rax,rcx
 ret
.eof:
 mov rax,-1
 ret
fake_write:
 mov rax,rsp
 and eax,15
 cmp eax,8
 jne bad_alignment
 mov rdx,[captured_len]
 lea rcx,[rdx+rsi]
 cmp rcx,8191
 ja bad_alignment
 lea r8,[captured]
 add r8,rdx
 xor edx,edx
.copy:
 cmp rdx,rsi
 jae .done
 mov al,[rdi+rdx]
 mov [r8+rdx],al
 inc rdx
 jmp .copy
.done:
 mov [captured_len],rcx
 lea rax,[captured]
 mov byte [rax+rcx],0
 ret
bad_read:
 mov qword [failed],1
 mov rax,-3
 ret
bad_alignment:
 mov qword [failed],1
 ret
section .note.GNU-stack noalloc noexec nowrite progbits
