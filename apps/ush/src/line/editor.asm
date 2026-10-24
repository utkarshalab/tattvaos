; Shared ASCII/VT line editor. Frontends supply blocking get_char and write.
; All editor state is serialized with the shell. The kernel pins console/log
; fibers to the BSP, so log hooks run only at input-idle yield points.
%include "inc/ush.inc"
bits 64
default rel
extern uedit_active,uedit_log_begin,uedit_redraw
extern frontend_write_str,frontend_write,frontend_get_char,history_get,calc_format
section .rodata
clear_line: db 13,27,'[2K',0
newline: db 10,0
cancel: db '^C',10,0
bell: db 7,0
csi: db 27,'[',0
cursor_left: db 'D',0
section .bss
line_prompt: resq 1
line_history: resq 1
line_active: resq 1
line_buffer: resq 1
line_capacity: resq 1
line_length: resq 1
line_cursor: resq 1
line_view: resq 1
line_invalid: resq 1
line_escape: resq 1
line_parameter: resq 1
line_age: resq 1
line_draft: resb USH_MAX_LINE_LEN
draft_length: resq 1
draft_cursor: resq 1
cursor_number: resb 67
section .text
global line_init,frontend_set_prompt,line_readline,line_log_begin,line_log_end
line_init:
 mov qword [line_active],0
 mov qword [line_prompt],0
 mov qword [line_history],0
 ret
; rdi=static prompt, rsi=allow shell history navigation (0/1).
frontend_set_prompt:
 mov [line_prompt],rdi
 mov [line_history],rsi
 ret
line_log_begin:
 cmp qword [uedit_active],0
 jne uedit_log_begin
 cmp qword [line_active],0
 je .done
 lea rdi,[clear_line]
 jmp frontend_write_str
.done: ret
line_log_end:
 cmp qword [uedit_active],0
 jne uedit_redraw
 cmp qword [line_active],0
 je .done
 jmp line_redraw
.done: ret
line_redraw:
 ; ponytail: 64-column ASCII viewport; query frontend.get_size for narrow terminals.
 push rbx
 push r12
 push r13
 lea rdi,[clear_line]
 call frontend_write_str
 mov rdi,[line_prompt]
 test rdi,rdi
 jz .text
 call frontend_write_str
.text:
 mov rax,[line_cursor]
 mov rbx,[line_view]
 cmp rax,rbx
 jae .right_bound
 mov rbx,rax
.right_bound:
 lea rcx,[rbx+64]
 cmp rax,rcx
 jb .view_ok
 lea rbx,[rax-63]
.view_ok:
 mov [line_view],rbx
 mov r12,[line_length]
 sub r12,rbx
 cmp r12,64
 jbe .count_ok
 mov r12d,64
.count_ok:
 mov rdi,[line_buffer]
 add rdi,rbx
 mov rsi,r12
 call frontend_write
 mov r13,[line_cursor]
 sub r13,rbx
 mov rdi,r12
 sub rdi,r13
 jz .done
 mov esi,10
 lea rdx,[cursor_number]
 call calc_format
 lea rdi,[csi]
 call frontend_write_str
 lea rdi,[cursor_number]
 call frontend_write_str
 lea rdi,[cursor_left]
 call frontend_write_str
.done:
 pop r13
 pop r12
 pop rbx
 ret
line_readline:
 push rbx
 push rbp
 push r12
 push r13
 push r14
 push r15
 sub rsp,8
 test rdi,rdi
 jz .io
 cmp rsi,1
 jb .io
 cmp rsi,USH_MAX_LINE_LEN
 ja .io
 mov [line_buffer],rdi
 mov [line_capacity],rsi
 mov byte [rdi],0
 mov qword [line_length],0
 mov qword [line_cursor],0
 mov qword [line_view],0
 mov qword [line_invalid],0
 mov qword [line_escape],0
 mov qword [line_age],-1
 mov qword [line_active],1
 call line_redraw
.read:
 call frontend_get_char
 cmp rax,-1
 je .eof
 test rax,rax
 js .io
 mov r12d,eax
 cmp eax,3
 je .cancel
 cmp eax,4
 je .ctrl_d
 cmp eax,13
 je .enter
 cmp eax,10
 je .enter
 cmp eax,27
 je .escape
 cmp eax,1
 je .home
 cmp eax,5
 je .end
 cmp eax,21
 je .clear
 cmp eax,11
 je .kill
 cmp eax,8
 je .backspace
 cmp eax,127
 je .backspace
 cmp qword [line_escape],0
 jne .sequence
 cmp eax,32
 jb .invalid_control
 cmp eax,126
 ja .beep
 mov rbx,[line_length]
 mov rcx,[line_capacity]
 dec rcx
 cmp rbx,rcx
 jae .overflow
 mov rdi,[line_buffer]
 mov rcx,[line_cursor]
 mov rdx,rbx
.insert:
 cmp rdx,rcx
 jb .insert_char
 mov al,[rdi+rdx]
 mov [rdi+rdx+1],al
 test rdx,rdx
 jz .insert_char
 dec rdx
 jmp .insert
.insert_char:
 mov [rdi+rcx],r12b
 inc qword [line_length]
 inc qword [line_cursor]
 mov qword [line_age],-1
 jmp .redraw
.invalid_control:
 test eax,eax
 jnz .beep
.overflow:
 mov qword [line_invalid],1
.beep:
 lea rdi,[bell]
 call frontend_write_str
 jmp .read
.escape:
 mov qword [line_escape],1
 mov qword [line_parameter],0
 jmp .read
.sequence:
 mov rcx,[line_escape]
 cmp rcx,1
 jne .csi
 cmp eax,'['
 je .csi_start
 cmp eax,'O'
 je .csi_start
 mov qword [line_escape],0
 jmp .read
.csi_start:
 mov qword [line_escape],2
 jmp .read
.csi:
 cmp eax,'0'
 jb .csi_final
 cmp eax,'9'
 ja .csi_final
 sub eax,'0'
 mov rcx,[line_parameter]
 imul rcx,rcx,10
 add rcx,rax
 cmp rcx,999
 ja .sequence_reset
 mov [line_parameter],rcx
 jmp .read
.csi_final:
 mov qword [line_escape],0
 cmp eax,'A'
 je .up
 cmp eax,'B'
 je .down
 cmp eax,'C'
 je .right
 cmp eax,'D'
 je .left
 cmp eax,'H'
 je .home
 cmp eax,'F'
 je .end
 cmp eax,'~'
 jne .read
 mov rax,[line_parameter]
 cmp rax,3
 je .delete
 cmp rax,1
 je .home
 cmp rax,7
 je .home
 cmp rax,4
 je .end
 cmp rax,8
 je .end
 jmp .read
.sequence_reset:
 mov qword [line_escape],0
 jmp .read
.left:
 cmp qword [line_cursor],0
 je .read
 dec qword [line_cursor]
 jmp .redraw
.right:
 mov rax,[line_cursor]
 cmp rax,[line_length]
 jae .read
 inc qword [line_cursor]
 jmp .redraw
.home:
 mov qword [line_cursor],0
 jmp .redraw
.end:
 mov rax,[line_length]
 mov [line_cursor],rax
 jmp .redraw
.backspace:
 cmp qword [line_cursor],0
 je .read
 dec qword [line_cursor]
.delete:
 mov rcx,[line_cursor]
 mov rbx,[line_length]
 cmp rcx,rbx
 jae .read
 mov rdi,[line_buffer]
.shift:
 mov al,[rdi+rcx+1]
 mov [rdi+rcx],al
 inc rcx
 cmp rcx,rbx
 jb .shift
 dec qword [line_length]
 mov qword [line_age],-1
 jmp .redraw
.ctrl_d:
 cmp qword [line_length],0
 je .eof
 jmp .delete
.clear:
 mov rdi,[line_buffer]
 mov byte [rdi],0
 mov qword [line_length],0
 mov qword [line_cursor],0
 mov qword [line_invalid],0
 mov qword [line_age],-1
 jmp .redraw
.kill:
 mov rax,[line_cursor]
 mov [line_length],rax
 mov rdi,[line_buffer]
 mov byte [rdi+rax],0
 mov qword [line_age],-1
 jmp .redraw
.up:
 cmp qword [line_history],0
 je .read
 mov rdi,[line_age]
 inc rdi
 call history_get
 test rax,rax
 jz .read
 mov r13,rax
 cmp qword [line_age],-1
 jne .recall_up
 mov rsi,[line_buffer]
 lea rdi,[line_draft]
 mov rcx,[line_length]
 mov [draft_length],rcx
 mov rax,[line_cursor]
 mov [draft_cursor],rax
 inc rcx
 rep movsb
.recall_up:
 inc qword [line_age]
 mov rsi,r13
 jmp .load_history
.down:
 cmp qword [line_age],-1
 je .read
 dec qword [line_age]
 cmp qword [line_age],-1
 je .draft
 mov rdi,[line_age]
 call history_get
 test rax,rax
 jz .read
 mov rsi,rax
 jmp .load_history
.draft:
 lea rsi,[line_draft]
.load_history:
 mov rdi,[line_buffer]
 xor ecx,ecx
.copy_history:
 mov al,[rsi+rcx]
 mov [rdi+rcx],al
 test al,al
 jz .history_done
 inc rcx
 cmp rcx,[line_capacity]
 jb .copy_history
 ; History is disabled in the smaller calculator input buffer.
 jmp .io
.history_done:
 mov [line_length],rcx
 mov [line_cursor],rcx
 cmp qword [line_age],-1
 jne .redraw
 mov rax,[draft_cursor]
 mov [line_cursor],rax
.redraw:
 mov qword [line_escape],0
 call line_redraw
 jmp .read
.cancel:
 mov qword [line_active],0
 mov rdi,[line_buffer]
 mov byte [rdi],0
 lea rdi,[clear_line]
 call frontend_write_str
 mov rdi,[line_prompt]
 test rdi,rdi
 jz .cancel_text
 call frontend_write_str
.cancel_text:
 lea rdi,[cancel]
 call frontend_write_str
 mov rax,-4
 jmp .return
.eof:
 cmp qword [line_length],0
 jne .enter
 mov qword [line_active],0
 lea rdi,[newline]
 call frontend_write_str
 mov rax,-1
 jmp .return
.enter:
 mov qword [line_active],0
 lea rdi,[newline]
 call frontend_write_str
 cmp qword [line_invalid],0
 jne .bad_line
 mov rax,[line_length]
 jmp .return
.bad_line:
 mov rax,-2
 jmp .return
.io:
 mov qword [line_active],0
 mov rax,-3
.return:
 add rsp,8
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbp
 pop rbx
 ret
section .note.GNU-stack noalloc noexec nowrite progbits
