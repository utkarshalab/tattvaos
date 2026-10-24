; UXFS/frontend adapter only. The editing engine and terminal UI live in Uedit.
%include "inc/frontend.inc"
%include "storage/uxfs/volume.inc"
%include "apps/uedit/inc/uedit.inc"
bits 64
default rel
extern ush_interactive,ush_frontend,frontend_get_char,frontend_write,frontend_write_str
extern uxv_ready,uxv_normalize,uxv_find,uxv_free,uxv_commit,uedit_run
section .bss
path: resb 240
columns: resq 1
rows: resq 1
section .data.rel.ro
io: dq frontend_get_char,frontend_write,save,size
section .rodata
error: db 'uedit: requires a terminal, valid UXFS path and UTF-8/LF/CRLF/TAB text (max 4096 bytes)',10,0
section .text
global cmd_uedit
cmd_uedit:
 push rbx
 push r12
 push r13
 mov r13,rsi
 cmp qword [ush_interactive],1
 jne .bad
 mov rax,[ush_frontend]
 test rax,rax
 jz .bad
 cmp qword [rax+io_frontend_t.get_char],0
 je .bad
.terminal_ready:
 cmp qword [uxv_ready],1
 jne .bad
 mov rdi,[r13+8]
 lea rsi,[path]
 call uxv_normalize
 test rax,rax
 js .bad
 lea rdi,[path]
 call uxv_find
 xor r8d,r8d
 test rax,rax
 jz .new
 cmp qword [rax+UV_TYPE],1
 jne .bad
 lea rsi,[rax+UV_DATA]
 mov rdx,[rax+UV_SIZE]
 jmp .run
.new:
 xor esi,esi
 xor edx,edx
 mov r8d,1
.run:
 lea rdi,[io]
 lea rcx,[path]
 call uedit_run
 test rax,rax
 js .bad
 jmp .done
.bad:
 lea rdi,[error]
 call frontend_write_str
 mov eax,1
.done:
 pop r13
 pop r12
 pop rbx
 ret
size:
 mov rax,[ush_frontend]
 mov rax,[rax+io_frontend_t.get_size]
 test rax,rax
 jz .done
 jmp rax
.done: ret
; Snapshot save. The app buffer is never borrowed by the volume. A failed
; commit disables the volume; Uedit retains the document and its dirty flag.
save:
 push rbx
 push r12
 push r13
 mov r12,rdi
 mov r13,rsi
 cmp r13,UE_CAPACITY
 ja .bad
 cmp qword [uxv_ready],1
 jne .bad
 lea rdi,[path]
 call uxv_find
 test rax,rax
 jz .allocate
 cmp qword [rax+UV_TYPE],1
 jne .bad
 mov rbx,rax
 jmp .copy
.allocate:
 call uxv_free
 test rax,rax
 jz .bad
 mov rbx,rax
 mov rdi,rax
 xor eax,eax
 mov ecx,UV_NODE/8
 rep stosq
 lea rsi,[path]
 mov rdi,rbx
 mov ecx,240
 rep movsb
 mov qword [rbx+UV_TYPE],1
.copy:
 lea rdi,[rbx+UV_DATA]
 mov rsi,r12
 mov rcx,r13
 rep movsb
 mov ecx,UE_CAPACITY
 sub rcx,r13
 xor eax,eax
 rep stosb
 mov [rbx+UV_SIZE],r13
 call uxv_commit
 jmp .done
.bad: mov rax,-1
.done:
 pop r13
 pop r12
 pop rbx
 ret
section .note.GNU-stack noalloc noexec nowrite progbits
