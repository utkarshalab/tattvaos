; Session actions: 64 bounded snapshots, owned clipboard, literal search/replace.
%include "inc/uedit.inc"
bits 64
default rel
extern uedit_key,ue_replace
section .bss
history: resb 64*uedit_context_size
history_count: resq 1
history_index: resq 1
saved_data: resb UE_CAPACITY
saved_length: resq 1
saved_exists: resq 1
clipboard: resb UE_CAPACITY
clipboard_length: resq 1
replacement: resb UE_CAPACITY
global ue_anchor
ue_anchor: resq 1
section .text
global ue_reset,ue_record,ue_saved,ue_dirty,ue_undo,ue_redo,ue_action,ue_find,ue_change
; (ctx,newfile)
ue_reset:
 push rbx
 mov rbx,rdi
 mov qword [ue_anchor],-1
 mov qword [clipboard_length],0
 mov qword [history_count],0
 mov qword [history_index],0
 xor eax,eax
 test rsi,rsi
 sete al
 mov [saved_exists],rax
 call ue_saved.copy
 mov rdi,rbx
 call ue_record
 pop rbx
 ret
ue_saved:
 mov qword [saved_exists],1
.copy:
 mov rax,[rdi+uedit_context.length]
 mov [saved_length],rax
 mov rcx,rax
 lea rsi,[rdi+uedit_context.data]
 lea rdi,[saved_data]
 rep movsb
 ret
ue_dirty:
 mov qword [rdi+uedit_context.dirty],1
 cmp qword [saved_exists],0
 je .done
 mov rcx,[rdi+uedit_context.length]
 cmp rcx,[saved_length]
 jne .done
 push rdi
 lea rsi,[saved_data]
 lea rdi,[rdi+uedit_context.data]
 repe cmpsb
 pop rdi
 jne .done
 mov qword [rdi+uedit_context.dirty],0
.done: ret
ue_record:
 push rbx
 mov rbx,rdi
 mov rax,[history_index]
 cmp qword [history_count],0
 je .first
 inc rax
.first:
 cmp rax,64
 jb .copy
 lea rsi,[history+uedit_context_size]
 lea rdi,[history]
 mov ecx,63*uedit_context_size
 rep movsb
 mov eax,63
.copy:
 mov [history_index],rax
 lea rcx,[rax+1]
 mov [history_count],rcx
 imul rax,uedit_context_size
 lea rdi,[history]
 add rdi,rax
 mov rsi,rbx
 mov ecx,uedit_context_size
 rep movsb
 mov rdi,rbx
 call ue_dirty
 pop rbx
 ret
ue_undo:
 mov rax,[history_index]
 test rax,rax
 jz .empty
 dec rax
 jmp restore
.empty: xor eax,eax
 ret
ue_redo:
 mov rax,[history_index]
 inc rax
 cmp rax,[history_count]
 jae ue_undo.empty
restore:
 mov [history_index],rax
 imul rax,uedit_context_size
 lea rsi,[history]
 add rsi,rax
 push rdi
 mov ecx,uedit_context_size
 rep movsb
 pop rdi
 mov qword [ue_anchor],-1
 sub rsp,8
 call ue_dirty
 add rsp,8
 mov eax,1
 ret
; ctx -> rsi=start,rdx=end,CF=selection exists
selection:
 mov rsi,[ue_anchor]
 cmp rsi,-1
 je .none
 mov rdx,[rdi+uedit_context.cursor]
 cmp rsi,rdx
 je .none
 jb .yes
 xchg rsi,rdx
.yes: stc
 ret
.none: clc
 ret
; (ctx,key) -> core status; Ctrl-B mark, Ctrl-C copy, Ctrl-X cut, Ctrl-V paste.
ue_action:
 push rbx
 push r12
 push r13
 mov rbx,rdi
 mov r12,rsi
 cmp esi,2
 je .mark
 cmp esi,3
 je .copy
 cmp esi,24
 je .cut
 cmp esi,22
 je .paste
 ; Typing/backspace/delete replaces an active selection in one history step.
 cmp esi,UE_BACKSPACE
 je .selected_delete
 cmp esi,UE_DELETE
 je .selected_delete
 cmp esi,UE_LEFT
 jb .typing
 cmp esi,UE_PAGEDOWN
 jbe .ordinary
.typing:
 ; Let core encode/validate the key in a temporary empty context, then paste.
 call selection
 jnc .ordinary
 sub rsp,UE_CONTEXT_ALLOC
 mov r13,rsp
 mov rdi,rsp
 xor eax,eax
 mov ecx,uedit_context_size/8
 rep stosq
 mov rax,[rbx+uedit_context.crlf]
 mov [r13+uedit_context.crlf],rax
 mov rdi,r13
 mov rsi,r12
 call uedit_key
 cmp rax,1
 jne .temp_done
 mov rdi,rbx
 call selection
 lea rcx,[r13+uedit_context.data]
 mov r8,[r13+uedit_context.length]
 call ue_replace
.temp_done:
 add rsp,UE_CONTEXT_ALLOC
 jmp .record
.selected_delete:
 call selection
 jnc .ordinary
 xor ecx,ecx
 xor r8d,r8d
 call ue_replace
 jmp .record
.ordinary:
 mov rdi,rbx
 mov rsi,r12
 call uedit_key
 jmp .record
.mark:
 mov rax,[rbx+uedit_context.cursor]
 cmp qword [ue_anchor],-1
 je .set_mark
 mov rax,-1
.set_mark: mov [ue_anchor],rax
 xor eax,eax
 jmp .done
.copy:
 call selection
 jnc .noop
 mov rcx,rdx
 sub rcx,rsi
 mov [clipboard_length],rcx
 lea rsi,[rbx+uedit_context.data+rsi]
 lea rdi,[clipboard]
 rep movsb
 mov qword [ue_anchor],-1
 jmp .noop
.cut:
 call selection
 jnc .noop
 push rsi
 push rdx
 mov rcx,rdx
 sub rcx,rsi
 mov [clipboard_length],rcx
 lea rsi,[rbx+uedit_context.data+rsi]
 lea rdi,[clipboard]
 rep movsb
 pop rdx
 pop rsi
 mov rdi,rbx
 xor ecx,ecx
 xor r8d,r8d
 call ue_replace
 jmp .record
.paste:
 cmp qword [clipboard_length],0
 je .noop
 call selection
 jc .paste_range
 mov rsi,[rbx+uedit_context.cursor]
 mov rdx,rsi
.paste_range:
 lea rcx,[clipboard]
 mov r8,[clipboard_length]
 call ue_replace
.record:
 cmp rax,1
 jne .done
 mov qword [ue_anchor],-1
 mov rdi,rbx
 call ue_record
 mov eax,1
 jmp .done
.noop: xor eax,eax
.done: pop r13
 pop r12
 pop rbx
 ret
; (ctx,query,len,start) -> match offset / -1; wraps once, never mutates.
ue_find:
 push rbx
 push r12
 push r13
 push r14
 push r15
 mov rbx,rdi
 mov r12,rsi
 mov r13,rdx
 mov r14,rcx
 xor r15d,r15d
 test rdx,rdx
 jz .missing
.loop:
 cmp r14,[rbx+uedit_context.length]
 ja .wrap
 mov rax,r14
 add rax,r13
 cmp rax,[rbx+uedit_context.length]
 ja .advance
 lea rdi,[rbx+uedit_context.data+r14]
 mov rsi,r12
 mov rcx,r13
 repe cmpsb
 je .found
.advance:
 inc r14
 cmp r15,[rbx+uedit_context.length]
 jae .missing
 inc r15
 jmp .loop
.wrap: xor r14d,r14d
 jmp .loop
.found: mov rax,r14
 jmp .done
.missing: mov rax,-1
.done: pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 ret
; (ctx,query,qlen,replacement,rlen,all) -> 1 changed,0 missing,-2 full.
; All replacement is built and capacity-checked before the one document mutation.
ue_change:
 push rbx
 push r12
 push r13
 push r14
 push r15
 sub rsp,64
 mov rbx,rdi
 mov r12,rsi
 mov r13,rdx
 mov [rsp],rcx
 mov [rsp+8],r8
 mov [rsp+16],r9
 mov qword [rsp+24],0
 mov qword [rsp+32],0
 xor r14d,r14d
 xor r15d,r15d
 test r13,r13
 jz .missing
 cmp r9,0
 jne .loop
 mov rcx,[rbx+uedit_context.cursor]
 call ue_find
 test rax,rax
 js .missing
 mov [rsp+32],rax
.loop:
 cmp r14,[rbx+uedit_context.length]
 jae .apply
 cmp qword [rsp+16],0
 jne .compare
 cmp qword [rsp+24],0
 jne .byte
 cmp r14,[rsp+32]
 jne .byte
.compare:
 mov rax,r14
 add rax,r13
 cmp rax,[rbx+uedit_context.length]
 ja .byte
 lea rdi,[rbx+uedit_context.data+r14]
 mov rsi,r12
 mov rcx,r13
 repe cmpsb
 jne .byte
 mov rax,r15
 add rax,[rsp+8]
 cmp rax,UE_CAPACITY
 ja .full
 lea rdi,[replacement]
 add rdi,r15
 mov rsi,[rsp]
 mov rcx,[rsp+8]
 rep movsb
 mov r15,rax
 add r14,r13
 inc qword [rsp+24]
 jmp .loop
.byte:
 cmp r15,UE_CAPACITY
 jae .full
 mov al,[rbx+uedit_context.data+r14]
 lea rdi,[replacement]
 mov [rdi+r15],al
 inc r14
 inc r15
 jmp .loop
.apply:
 cmp qword [rsp+24],0
 je .missing
 mov rdi,rbx
 xor esi,esi
 mov rdx,[rbx+uedit_context.length]
 lea rcx,[replacement]
 mov r8,r15
 call ue_replace
 cmp qword [rsp+16],0
 jne .positioned
 mov rax,[rsp+32]
 add rax,[rsp+8]
 mov [rbx+uedit_context.cursor],rax
.positioned:
 mov qword [ue_anchor],-1
 mov rdi,rbx
 call ue_record
 mov eax,1
 jmp .done
.full: mov rax,-2
 jmp .done
.missing: xor eax,eax
.done: add rsp,64
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 ret
section .note.GNU-stack noalloc noexec nowrite progbits
