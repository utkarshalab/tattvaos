; Fixed-capacity event model. No persistence or callbacks; caller serializes.
%include "inc/calender.inc"
bits 64
default rel
extern str_utf8_decode
section .text
global ucal_store_init,ucal_event_put,ucal_event_get,ucal_event_delete,ucal_event_query
ucal_store_init:
 test rdi,rdi
 jz invalid
 mov qword [rdi],1
 add rdi,8
 xor eax,eax
 mov ecx,UCAL_EVENTS*ucal_event_size/8
 rep stosq
 ret
invalid: mov rax,UCAL_INVALID
 ret
; Internal (store,id) -> pointer or zero. No mutation.
lookup:
 lea rax,[rdi+ucal_store.events]
 mov ecx,UCAL_EVENTS
.loop:
 cmp [rax+ucal_event.id],rsi
 je .done
 add rax,ucal_event_size
 dec ecx
 jnz .loop
 xor eax,eax
.done: ret
; (store,event with id=0 create or existing id update,out_id*)
ucal_event_put:
 push rbx
 push r12
 push r13
 push r14
 push r15
 sub rsp,16
 mov rbx,rdi
 mov r12,rsi
 mov r13,rdx
 test rdi,rdi
 jz .invalid
 test rsi,rsi
 jz .invalid
 test rdx,rdx
 jz .invalid
 cmp qword [rdi+ucal_store.next_id],0
 je .invalid
 mov rax,-62135596800
 cmp [rsi+ucal_event.start],rax
 jl .invalid
 mov rax,253402300800
 cmp [rsi+ucal_event.end],rax
 jg .invalid
 mov rax,[rsi+ucal_event.start]
 cmp rax,[rsi+ucal_event.end]
 jge .invalid
 cmp qword [rsi+ucal_event.flags],1
 ja .invalid
 cmp qword [rsi+ucal_event.flags],0
 je .title
 cqo
 mov ecx,86400
 idiv rcx
 test rdx,rdx
 jnz .invalid
 mov rax,[r12+ucal_event.end]
 cqo
 idiv rcx
 test rdx,rdx
 jnz .invalid
.title:
 xor r14d,r14d
.length:
 cmp r14,128
 jae .invalid
 cmp byte [r12+ucal_event.title+r14],0
 je .validate_title
 inc r14
 jmp .length
.validate_title:
 test r14,r14
 jz .invalid
 xor r15d,r15d
.scalar:
 cmp r15,r14
 jae .validated
 lea rdi,[r12+ucal_event.title+r15]
 mov rsi,r14
 sub rsi,r15
 mov rdx,rsp
 lea rcx,[rsp+8]
 call str_utf8_decode
 test rax,rax
 js .invalid
 mov eax,[rsp]
 cmp eax,32
 jb .invalid
 cmp eax,127
 jb .next
 cmp eax,159
 jbe .invalid
.next:
 add r15,[rsp+8]
 jmp .scalar
.validated:
 mov rdi,rbx
 mov rsi,[r12+ucal_event.id]
 test rsi,rsi
 jz .create
 call lookup
 test rax,rax
 jz .missing
 mov r15,[rax+ucal_event.id]
 jmp .copy
.create:
 mov r15,[rbx+ucal_store.next_id]
 cmp r15,-1
 je .range
 xor esi,esi
 call lookup
 test rax,rax
 jz .full
 inc qword [rbx+ucal_store.next_id]
.copy:
 mov rdi,rax
 mov rsi,r12
 mov ecx,ucal_event_size/8
 rep movsq
 mov [rax+ucal_event.id],r15
 lea rdi,[rax+ucal_event.title+r14+1]
 mov ecx,127
 sub rcx,r14
 xor eax,eax
 rep stosb
 mov [r13],r15
 xor eax,eax
 jmp .done
.invalid: mov rax,UCAL_INVALID
 jmp .done
.missing: mov rax,UCAL_NOT_FOUND
 jmp .done
.range: mov rax,UCAL_RANGE
 jmp .done
.full: mov rax,UCAL_FULL
.done: add rsp,16
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 ret
; (store,id,out_event) -> 0 / status; outputs unchanged on failure.
ucal_event_get:
 push rbx
 mov rbx,rdx
 test rdi,rdi
 jz .bad
 test rsi,rsi
 jz .bad
 test rdx,rdx
 jz .bad
 call lookup
 test rax,rax
 jz .missing
 mov rsi,rax
 mov rdi,rbx
 mov ecx,ucal_event_size/8
 rep movsq
 xor eax,eax
 jmp .done
.bad: mov rax,UCAL_INVALID
 jmp .done
.missing: mov rax,UCAL_NOT_FOUND
.done: pop rbx
 ret
ucal_event_delete:
 test rdi,rdi
 jz invalid
 test rsi,rsi
 jz invalid
 sub rsp,8
 call lookup
 add rsp,8
 test rax,rax
 jz .missing
 mov rdi,rax
 xor eax,eax
 mov ecx,ucal_event_size/8
 rep stosq
 ret
.missing: mov rax,UCAL_NOT_FOUND
 ret
; (store,from inclusive,to exclusive,out_ids,capacity,out_total)
; Returns number written; sorted start then id; count-only query permits NULL/0.
ucal_event_query:
 push rbx
 push r12
 push r13
 push r14
 push r15
 sub rsp,UCAL_EVENTS*8+32
 test rdi,rdi
 jz .bad
 test r9,r9
 jz .bad
 cmp rsi,rdx
 jge .bad
 test r8,r8
 jz .args
 test rcx,rcx
 jz .bad
.args:
 mov [rsp+512],rcx
 mov [rsp+520],r8
 mov [rsp+528],r9
 lea rbx,[rdi+ucal_store.events]
 xor r12d,r12d
 xor r13d,r13d
.scan:
 cmp qword [rbx+ucal_event.id],0
 je .next
 cmp [rbx+ucal_event.start],rdx
 jge .next
 cmp [rbx+ucal_event.end],rsi
 jle .next
 mov r14,r13
.insert:
 test r14,r14
 jz .place
 mov r15,[rsp+r14*8-8]
 mov rax,[rbx+ucal_event.start]
 cmp rax,[r15+ucal_event.start]
 jg .place
 jl .shift
 mov rax,[rbx+ucal_event.id]
 cmp rax,[r15+ucal_event.id]
 jae .place
.shift:
 mov [rsp+r14*8],r15
 dec r14
 jmp .insert
.place:
 mov [rsp+r14*8],rbx
 inc r13
.next:
 add rbx,ucal_event_size
 inc r12
 cmp r12,UCAL_EVENTS
 jb .scan
 mov rax,[rsp+528]
 mov [rax],r13
 cmp r13,[rsp+520]
 cmova r13,[rsp+520]
 mov rdi,[rsp+512]
 xor ecx,ecx
.copy:
 cmp rcx,r13
 jae .ok
 mov rax,[rsp+rcx*8]
 mov rax,[rax+ucal_event.id]
 mov [rdi+rcx*8],rax
 inc rcx
 jmp .copy
.ok: mov rax,r13
 jmp .done
.bad: mov rax,UCAL_INVALID
.done: add rsp,UCAL_EVENTS*8+32
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 ret
section .note.GNU-stack noalloc noexec nowrite progbits
