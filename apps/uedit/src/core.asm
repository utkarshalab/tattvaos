; Bounded UTF-8/CRLF editing. All positions are byte boundaries.
%include "inc/uedit.inc"
bits 64
default rel
extern ue_decode,ue_validate,ue_prev,ue_width,str_utf8_encode
section .text
global uedit_load,uedit_key,uedit_locate,uedit_line_start,ue_replace
global ue_page_rows
uedit_load:
 push rbx
 push r12
 push r13
 mov rbx,rdi
 mov r12,rsi
 mov r13,rdx
 test rdi,rdi
 jz .bad
 cmp rdx,UE_CAPACITY
 ja .bad
 test rdx,rdx
 jz .valid
 test rsi,rsi
 jz .bad
 mov rdi,rsi
 mov rsi,rdx
 call ue_validate
 test rax,rax
 js .bad
.valid:
 mov [rbx+uedit_context.length],r13
 mov qword [rbx+uedit_context.cursor],0
 mov qword [rbx+uedit_context.top],0
 mov qword [rbx+uedit_context.left],0
 mov qword [rbx+uedit_context.goal],-1
 mov qword [rbx+uedit_context.dirty],0
 mov qword [rbx+uedit_context.crlf],0
 xor ecx,ecx
.eol:
 cmp rcx,r13
 jae .copy
 cmp byte [r12+rcx],13
 je .windows
 inc rcx
 jmp .eol
.windows:
 mov qword [rbx+uedit_context.crlf],1
.copy:
 lea rdi,[rbx+uedit_context.data]
 mov rsi,r12
 mov rcx,r13
 rep movsb
 xor eax,eax
 jmp .done
.bad: mov rax,-1
.done: pop r13
 pop r12
 pop rbx
 ret
; ctx -> row rax, visual column rdx.
uedit_locate:
 push rbx
 push r12
 push r13
 push r14
 push r15
 mov rbx,rdi
 xor r12d,r12d
 xor r13d,r13d
 xor r14d,r14d
.loop:
 cmp r14,[rbx+uedit_context.cursor]
 jae .done
 lea rdi,[rbx+uedit_context.data+r14]
 mov rsi,[rbx+uedit_context.length]
 sub rsi,r14
 call ue_decode
 add r14,rdx
 cmp eax,10
 je .newline
 cmp eax,9
 je .tab
 call ue_width
 add r13,rax
 jmp .loop
.tab: add r13,4
 and r13,-4
 jmp .loop
.newline: inc r12
 xor r13d,r13d
 jmp .loop
.done: mov rax,r12
 mov rdx,r13
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 ret
uedit_line_start:
 xor eax,eax
 test rsi,rsi
 jz .done
.loop: cmp rax,[rdi+uedit_context.length]
 jae .done
 mov cl,[rdi+uedit_context.data+rax]
 inc rax
 cmp cl,10
 jne .loop
 dec rsi
 jnz .loop
.done: ret
; Atomic range replacement (ctx,start,end,bytes,count); valid fragments only.
; Internal callers supply existing scalar boundaries and validated UTF-8.
ue_replace:
 push rbx
 push r12
 push r13
 push r14
 push r15
 sub rsp,UE_CAPACITY
 mov rbx,rdi
 mov r12,rsi
 mov r13,rdx
 mov r14,rcx
 mov r15,r8
 cmp rsi,rdx
 ja .bad
 cmp rdx,[rbx+uedit_context.length]
 ja .bad
 mov rax,[rbx+uedit_context.length]
 sub rax,rdx
 add rax,rsi
 add rax,r8
 jc .full
 cmp rax,UE_CAPACITY
 ja .full
 mov rdi,rsp
 lea rsi,[rbx+uedit_context.data]
 mov rcx,r12
 rep movsb
 mov rsi,r14
 mov rcx,r15
 rep movsb
 lea rsi,[rbx+uedit_context.data+r13]
 mov rcx,[rbx+uedit_context.length]
 sub rcx,r13
 rep movsb
 mov [rbx+uedit_context.length],rax
 lea rdi,[rbx+uedit_context.data]
 mov rsi,rsp
 mov rcx,rax
 rep movsb
 add r12,r15
 mov [rbx+uedit_context.cursor],r12
 mov qword [rbx+uedit_context.dirty],1
 mov qword [rbx+uedit_context.goal],-1
 mov eax,1
 jmp .done
.full: mov rax,-2
 jmp .done
.bad: mov rax,-1
.done: add rsp,UE_CAPACITY
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 ret
uedit_key:
 push rbx
 push r12
 push r13
 push r14
 push r15
 sub rsp,16
 mov rbx,rdi
 mov r12,rsi
 mov r13,[rbx+uedit_context.cursor]
 cmp esi,UE_UP
 je .vertical
 cmp esi,UE_DOWN
 je .vertical
 cmp esi,UE_PAGEUP
 je .vertical
 cmp esi,UE_PAGEDOWN
 je .vertical
 mov qword [rbx+uedit_context.goal],-1
 cmp esi,UE_LEFT
 je .left
 cmp esi,UE_RIGHT
 je .right
 cmp esi,UE_HOME
 je .home
 cmp esi,UE_END
 je .end
 cmp esi,UE_DELETE
 je .delete
 cmp esi,UE_BACKSPACE
 je .backspace
 mov eax,esi
 cmp eax,UE_UNICODE
 jb .ascii
 sub eax,UE_UNICODE
 cmp eax,0x10ffff
 ja .bad
 cmp eax,160
 jb .bad
 cmp eax,0xd800
 jb .encode
 cmp eax,0xdfff
 jbe .bad
 jmp .encode
.ascii:
 cmp eax,10
 je .newline
 cmp eax,9
 je .encode
 cmp eax,32
 jb .bad
 cmp eax,126
 ja .bad
.encode:
 mov edi,eax
 mov rsi,rsp
 mov edx,8
 lea rcx,[rsp+8]
 call str_utf8_encode
 test rax,rax
 js .bad
 mov rcx,[rsp+8]
 jmp .insert
.newline:
 mov byte [rsp],10
 mov ecx,1
 cmp qword [rbx+uedit_context.crlf],0
 je .insert
.crlf:
 mov word [rsp],0x0a0d
 mov ecx,2
.insert:
 mov r8,rcx
 mov rcx,rsp
 mov rsi,r13
 mov rdx,r13
 mov rdi,rbx
 call ue_replace
 jmp .done
.left:
 lea rdi,[rbx+uedit_context.data]
 mov rsi,r13
 call ue_prev
 mov r13,rax
 jmp .move
.right:
 cmp r13,[rbx+uedit_context.length]
 jae .noop
 call .decode
 add r13,rdx
 jmp .move
.home:
 test r13,r13
 jz .move
 cmp byte [rbx+uedit_context.data+r13-1],10
 je .move
 lea rdi,[rbx+uedit_context.data]
 mov rsi,r13
 call ue_prev
 mov r13,rax
 jmp .home
.end:
 cmp r13,[rbx+uedit_context.length]
 jae .move
 call .decode
 cmp eax,10
 je .move
 add r13,rdx
 jmp .end
.backspace:
 test r13,r13
 jz .noop
 lea rdi,[rbx+uedit_context.data]
 mov rsi,r13
 call ue_prev
 mov rsi,rax
 mov rdx,r13
 jmp .remove
.delete:
 cmp r13,[rbx+uedit_context.length]
 jae .noop
 call .decode
 add rdx,r13
 mov rsi,r13
.remove:
 mov rdi,rbx
 xor ecx,ecx
 xor r8d,r8d
 call ue_replace
 jmp .done
.vertical:
 call uedit_locate
 mov r14,rax
 cmp qword [rbx+uedit_context.goal],-1
 jne .goal
 mov [rbx+uedit_context.goal],rdx
.goal:
 mov ecx,1
 cmp r12,UE_PAGEUP
 je .page
 cmp r12,UE_PAGEDOWN
 jne .direction
.page: mov rcx,[ue_page_rows]
.direction:
 cmp r12,UE_UP
 je .up
 cmp r12,UE_PAGEUP
 je .up
 add r14,rcx
 jmp .target
.up: sub r14,rcx
 jae .target
 xor r14d,r14d
.target:
 xor ecx,ecx
 xor edx,edx
.count:
 cmp rcx,[rbx+uedit_context.length]
 jae .clamp
 cmp byte [rbx+uedit_context.data+rcx],10
 jne .next
 inc rdx
.next: inc rcx
 jmp .count
.clamp:
 cmp r14,rdx
 cmova r14,rdx
 mov rdi,rbx
 mov rsi,r14
 call uedit_line_start
 mov r13,rax
 xor r15d,r15d
.column:
 cmp r13,[rbx+uedit_context.length]
 jae .move
 call .decode
 cmp eax,10
 je .move
 mov [rsp+8],rdx
 cmp eax,9
 je .tab
 call ue_width
 add rax,r15
 jmp .width
.tab: lea rax,[r15+4]
 and rax,-4
.width:
 cmp rax,[rbx+uedit_context.goal]
 ja .move
 cmp r15,[rbx+uedit_context.goal]
 jae .move
 mov r15,rax
 add r13,[rsp+8]
 jmp .column
.move: mov [rbx+uedit_context.cursor],r13
.noop: xor eax,eax
 jmp .done
.bad: mov rax,-1
.done: add rsp,16
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 ret
.decode:
 lea rdi,[rbx+uedit_context.data+r13]
 mov rsi,[rbx+uedit_context.length]
 sub rsi,r13
 jmp ue_decode
section .data
ue_page_rows: dq UE_ROWS
section .note.GNU-stack noalloc noexec nowrite progbits
