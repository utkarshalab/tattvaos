; UTC alarm queue. Polling coalesces missed periods; capacity causes backpressure.
%include "inc/clock.inc"
bits 64
default rel
section .text
global uclock_alarms_init,uclock_alarm_put,uclock_alarm_get,uclock_alarm_delete,uclock_alarm_poll
uclock_alarms_init:
 test rdi,rdi
 jz invalid
 mov qword [rdi],1
 add rdi,8
 xor eax,eax
 mov ecx,32*uclock_alarm_size/8
 rep stosq
 ret
invalid: mov rax,UCLOCK_INVALID
 ret
lookup:
 lea rax,[rdi+uclock_alarms.records]
 mov ecx,32
.loop:
 cmp [rax+uclock_alarm.id],rsi
 je .done
 add rax,uclock_alarm_size
 dec ecx
 jnz .loop
 xor eax,eax
.done: ret
; (store,alarm (id=0 create),out_id)
uclock_alarm_put:
 push rbx
 push r12
 push r13
 mov rbx,rsi
 mov r12,rdx
 test rdi,rdi
 jz .invalid
 test rsi,rsi
 jz .invalid
 test rdx,rdx
 jz .invalid
 cmp qword [rdi+uclock_alarms.next_id],0
 je .invalid
 mov rax,-62135596800
 cmp [rsi+uclock_alarm.due],rax
 jl .invalid
 mov rax,253402300799
 cmp [rsi+uclock_alarm.due],rax
 jg .invalid
 mov rax,315537897600
 cmp [rsi+uclock_alarm.period],rax
 ja .invalid
 cmp qword [rsi+uclock_alarm.enabled],1
 ja .invalid
 mov rsi,[rbx+uclock_alarm.id]
 test rsi,rsi
 jz .create
 call lookup
 test rax,rax
 jz .missing
 mov r13,[rax+uclock_alarm.id]
 jmp .copy
.create:
 mov r13,[rdi+uclock_alarms.next_id]
 cmp r13,-1
 je .range
 push rdi
 sub rsp,8
 xor esi,esi
 call lookup
 add rsp,8
 pop rdi
 test rax,rax
 jz .full
 inc qword [rdi+uclock_alarms.next_id]
.copy:
 mov rdi,rax
 mov rsi,rbx
 mov ecx,uclock_alarm_size/8
 rep movsq
 mov [rax+uclock_alarm.id],r13
 mov [r12],r13
 xor eax,eax
 jmp .done
.invalid: mov rax,UCLOCK_INVALID
 jmp .done
.missing: mov rax,UCLOCK_NOT_FOUND
 jmp .done
.full: mov rax,UCLOCK_FULL
 jmp .done
.range: mov rax,UCLOCK_RANGE
.done: pop r13
 pop r12
 pop rbx
 ret
uclock_alarm_get:
 push rbx
 mov rbx,rdx
 test rdi,rdi
 jz .invalid
 test rsi,rsi
 jz .invalid
 test rdx,rdx
 jz .invalid
 call lookup
 test rax,rax
 jz .missing
 mov rdi,rbx
 mov rsi,rax
 mov ecx,uclock_alarm_size/8
 rep movsq
 xor eax,eax
 jmp .done
.invalid: mov rax,UCLOCK_INVALID
 jmp .done
.missing: mov rax,UCLOCK_NOT_FOUND
.done: pop rbx
 ret
uclock_alarm_delete:
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
 mov ecx,uclock_alarm_size/8
 rep stosq
 ret
.missing: mov rax,UCLOCK_NOT_FOUND
 ret
; (store,now UTC seconds,out notifications,capacity) -> count or negative error.
; No callback/reentrancy; consumed records advance only when emitted.
uclock_alarm_poll:
 push rbx
 push r12
 push r13
 push r14
 push r15
 test rdi,rdi
 jz .invalid
 test rcx,rcx
 jz .empty
 test rdx,rdx
 jz .invalid
 mov rax,-62135596800
 cmp rsi,rax
 jl .invalid
 mov rax,253402300799
 cmp rsi,rax
 jg .invalid
 mov rbx,rdi
 mov r12,rsi
 mov r13,rdx
 mov r14,rcx
 cmp r14,32
 jbe .limit
 mov r14d,32
.limit:
 xor r15d,r15d
.emit:
 lea rdi,[rbx+uclock_alarms.records]
 mov ecx,32
 xor r8d,r8d
.scan:
 cmp qword [rdi+uclock_alarm.id],0
 je .next
 cmp qword [rdi+uclock_alarm.enabled],1
 jne .next
 cmp [rdi+uclock_alarm.due],r12
 jg .next
 test r8,r8
 jz .choose
 mov rax,[rdi+uclock_alarm.due]
 cmp rax,[r8+uclock_alarm.due]
 jg .next
 jl .choose
 mov rax,[rdi+uclock_alarm.id]
 cmp rax,[r8+uclock_alarm.id]
 jae .next
.choose: mov r8,rdi
.next:
 add rdi,uclock_alarm_size
 dec ecx
 jnz .scan
 test r8,r8
 jz .ok
 mov rax,[r8+uclock_alarm.id]
 mov [r13+uclock_notification.id],rax
 mov r9,[r8+uclock_alarm.due]
 mov [r13+uclock_notification.scheduled],r9
 mov [r13+uclock_notification.observed],r12
 mov qword [r13+uclock_notification.missed],0
 mov rcx,[r8+uclock_alarm.period]
 test rcx,rcx
 jz .disable
 mov rax,r12
 sub rax,r9
 xor edx,edx
 div rcx
 mov [r13+uclock_notification.missed],rax
 ; Next due = now + period - remainder, bounded signed civil epoch domain.
 sub rcx,rdx
 add rcx,r12
 mov rax,253402300799
 cmp rcx,rax
 jg .disable
 mov [r8+uclock_alarm.due],rcx
 jmp .emitted
.disable: mov qword [r8+uclock_alarm.enabled],0
.emitted:
 inc r15
 add r13,uclock_notification_size
 cmp r15,r14
 jb .emit
.ok: mov rax,r15
 jmp .done
.empty: xor eax,eax
 jmp .done
.invalid: mov rax,UCLOCK_INVALID
.done: pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 ret
section .note.GNU-stack noalloc noexec nowrite progbits
