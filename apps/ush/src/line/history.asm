; Bounded in-memory history. Added before parsing; excludes blank/oversized input.
%include "inc/ush.inc"
bits 64
default rel
extern frontend_write_str
section .bss
history_slots: resb 32*USH_MAX_LINE_LEN
history_count: resq 1
history_next: resq 1
section .rodata
history_newline: db 10,0
section .text
global history_init,history_add,history_print,history_get
; rdi=age (0 newest) -> rax=borrowed line or NULL.
history_get:
 cmp rdi,[history_count]
 jae .missing
 mov rax,[history_next]
 dec rax
 sub rax,rdi
 and eax,31
 imul rax,USH_MAX_LINE_LEN
 lea rdx,[history_slots]
 add rax,rdx
 ret
.missing:
 xor eax,eax
 ret
history_init:
 mov qword [history_count],0
 mov qword [history_next],0
 xor eax,eax
 ret
history_add:
 xor ecx,ecx
 xor r8d,r8d
.scan:
 mov al,[rdi+rcx]
 test al,al
 jz .copy
 cmp al,32
 je .space
 cmp al,9
 je .space
 mov r8d,1
.space:
 inc ecx
 cmp ecx,USH_MAX_LINE_LEN
 jb .scan
 mov rax,-1
 ret
.copy:
 test r8d,r8d
 jz .empty
 mov rsi,rdi
 mov rax,[history_next]
 imul rax,USH_MAX_LINE_LEN
 lea rdi,[history_slots]
 add rdi,rax
 inc ecx
 rep movsb
 mov rax,[history_next]
 inc eax
 and eax,31
 mov [history_next],rax
 cmp qword [history_count],32
 jae .empty
 inc qword [history_count]
.empty:
 xor eax,eax
 ret
history_print:
 push rbx
 push r12
 sub rsp,8
 mov r12,[history_count]
 xor ebx,ebx
 cmp r12,32
 jb .loop
 mov rbx,[history_next]
.loop:
 test r12,r12
 jz .done
 imul rax,rbx,USH_MAX_LINE_LEN
 lea rdi,[history_slots]
 add rdi,rax
 call frontend_write_str
 lea rdi,[history_newline]
 call frontend_write_str
 inc ebx
 and ebx,31
 dec r12
 jmp .loop
.done:
 xor eax,eax
 add rsp,8
 pop r12
 pop rbx
 ret
section .note.GNU-stack noalloc noexec nowrite progbits
