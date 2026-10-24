; Model-only clock API. Caller-owned contexts and explicit monotonic samples.
%include "apps/clock/inc/clock.inc"
bits 64
default rel
section .text
global uclock_read,uclock_stopwatch_init,uclock_stopwatch_start
global uclock_stopwatch_pause,uclock_stopwatch_read,uclock_stopwatch_lap
global uclock_countdown_init,uclock_countdown_start,uclock_countdown_poll
global uclock_countdown_pause,uclock_countdown_resume,uclock_duration_parts
; (sources*,sample*) -> 0/status. Callbacks fn(out*) -> 0/status.
uclock_read:
 push rbx
 push r12
 push r13
 sub rsp,32
 mov rbx,rdi
 mov r12,rsi
 test rdi,rdi
 jz .bad
 test rsi,rsi
 jz .bad
 cmp qword [rdi+uclock_sources.monotonic],0
 je .unavailable
 cmp qword [rdi+uclock_sources.realtime],0
 je .unavailable
 mov rdi,rsp
 call [rbx+uclock_sources.monotonic]
 test rax,rax
 jnz .unavailable
 lea rdi,[rsp+8]
 call [rbx+uclock_sources.realtime]
 test rax,rax
 jnz .unavailable
 cmp qword [rsp+16],1000000000
 jae .range
 mov rax,-62135596800
 cmp [rsp+8],rax
 jl .range
 mov rax,253402300799
 cmp [rsp+8],rax
 jg .range
 mov rdi,r12
 mov rsi,rsp
 mov ecx,3
 rep movsq
 xor eax,eax
 jmp .done
.bad: mov rax,UCLOCK_INVALID
 jmp .done
.unavailable: mov rax,UCLOCK_STATE
 jmp .done
.range: mov rax,UCLOCK_RANGE
.done: add rsp,32
 pop r13
 pop r12
 pop rbx
 ret
uclock_stopwatch_init:
 test rdi,rdi
 jz uclock_model_invalid
 xor eax,eax
 mov ecx,uclock_stopwatch_size/8
 rep stosq
 ret
uclock_model_invalid: mov rax,UCLOCK_INVALID
 ret
uclock_model_range: mov rax,UCLOCK_RANGE
 ret
uclock_model_state: mov rax,UCLOCK_STATE
 ret
uclock_stopwatch_start:
 test rdi,rdi
 jz uclock_model_invalid
 cmp rsi,[rdi+uclock_stopwatch.last]
 jb uclock_model_range
 cmp qword [rdi+uclock_stopwatch.state],0
 je .start
 cmp qword [rdi+uclock_stopwatch.state],2
 jne uclock_model_state
 cmp rsi,[rdi+uclock_stopwatch.last]
 jb uclock_model_range
.start:
 mov [rdi+uclock_stopwatch.anchor],rsi
 mov [rdi+uclock_stopwatch.last],rsi
 mov qword [rdi+uclock_stopwatch.state],1
 xor eax,eax
 ret
; (watch,now,out elapsed ns); read updates monotonic regression guard only.
uclock_stopwatch_read:
 test rdi,rdi
 jz uclock_model_invalid
 test rdx,rdx
 jz uclock_model_invalid
 cmp qword [rdi+uclock_stopwatch.state],2
 ja uclock_model_state
 cmp rsi,[rdi+uclock_stopwatch.last]
 jb uclock_model_range
 mov rax,[rdi+uclock_stopwatch.elapsed]
 cmp qword [rdi+uclock_stopwatch.state],1
 jne .write
 mov rcx,rsi
 sub rcx,[rdi+uclock_stopwatch.anchor]
 add rax,rcx
 jc uclock_model_range
.write:
 mov [rdi+uclock_stopwatch.last],rsi
 mov [rdx],rax
 xor eax,eax
 ret
uclock_stopwatch_pause:
 test rdi,rdi
 jz uclock_model_invalid
 cmp qword [rdi+uclock_stopwatch.state],1
 jne uclock_model_state
 push rbx
 sub rsp,16
 mov rbx,rdi
 mov rdx,rsp
 call uclock_stopwatch_read
 test rax,rax
 js .done
 mov rax,[rsp]
 mov [rbx+uclock_stopwatch.elapsed],rax
 mov qword [rbx+uclock_stopwatch.state],2
 xor eax,eax
.done: add rsp,16
 pop rbx
 ret
uclock_stopwatch_lap:
 test rdi,rdi
 jz uclock_model_invalid
 test rdx,rdx
 jz uclock_model_invalid
 cmp qword [rdi+uclock_stopwatch.state],1
 jne uclock_model_state
 cmp qword [rdi+uclock_stopwatch.lap_count],32
 jae .full
 push rbx
 push r12
 sub rsp,24
 mov rbx,rdi
 mov r12,rdx
 mov rdx,rsp
 call uclock_stopwatch_read
 test rax,rax
 js .done
 mov rcx,[rbx+uclock_stopwatch.lap_count]
 mov rdx,[rsp]
 mov [rbx+uclock_stopwatch.laps+rcx*8],rdx
 inc qword [rbx+uclock_stopwatch.lap_count]
 mov [r12],rdx
 xor eax,eax
.done: add rsp,24
 pop r12
 pop rbx
 ret
.full: mov rax,UCLOCK_FULL
 ret
uclock_countdown_init:
 test rdi,rdi
 jz uclock_model_invalid
 xor eax,eax
 mov ecx,uclock_countdown_size/8
 rep stosq
 ret
; (countdown,duration_ns,now_ns); start/rearm, no absolute deadline overflow.
uclock_countdown_start:
 test rdi,rdi
 jz uclock_model_invalid
 test rsi,rsi
 jz uclock_model_invalid
 mov [rdi+uclock_countdown.remaining],rsi
 mov [rdi+uclock_countdown.anchor],rdx
 mov [rdi+uclock_countdown.last],rdx
 mov qword [rdi+uclock_countdown.state],1
 xor eax,eax
 ret
; (countdown,now,out remaining) -> 1 just expired,0 otherwise,negative error.
uclock_countdown_poll:
 test rdi,rdi
 jz uclock_model_invalid
 test rdx,rdx
 jz uclock_model_invalid
 cmp qword [rdi+uclock_countdown.state],3
 ja uclock_model_state
 cmp rsi,[rdi+uclock_countdown.last]
 jb uclock_model_range
 xor eax,eax
 mov r8,[rdi+uclock_countdown.remaining]
 cmp qword [rdi+uclock_countdown.state],1
 jne .write
 mov rcx,rsi
 sub rcx,[rdi+uclock_countdown.anchor]
 cmp rcx,r8
 jae .expired
 sub r8,rcx
 jmp .anchor
.expired:
 xor r8d,r8d
 mov qword [rdi+uclock_countdown.state],3
 mov eax,1
.anchor:
 mov [rdi+uclock_countdown.anchor],rsi
 mov [rdi+uclock_countdown.remaining],r8
.write:
 mov [rdi+uclock_countdown.last],rsi
 mov [rdx],r8
 ret
uclock_countdown_pause:
 test rdi,rdi
 jz uclock_model_invalid
 cmp qword [rdi+uclock_countdown.state],1
 jne uclock_model_state
 push rbx
 sub rsp,16
 mov rbx,rdi
 mov rdx,rsp
 call uclock_countdown_poll
 test rax,rax
 jnz .done
 mov qword [rbx+uclock_countdown.state],2
.done: add rsp,16
 pop rbx
 ret
uclock_countdown_resume:
 test rdi,rdi
 jz uclock_model_invalid
 cmp qword [rdi+uclock_countdown.state],2
 jne uclock_model_state
 cmp rsi,[rdi+uclock_countdown.last]
 jb uclock_model_range
 mov [rdi+uclock_countdown.last],rsi
 mov [rdi+uclock_countdown.anchor],rsi
 mov qword [rdi+uclock_countdown.state],1
 xor eax,eax
 ret
; (duration_ns,out qwords[hours,minutes,seconds,nanoseconds])
uclock_duration_parts:
 test rsi,rsi
 jz uclock_model_invalid
 mov rax,rdi
 xor edx,edx
 mov ecx,1000000000
 div rcx
 mov [rsi+24],rdx
 xor edx,edx
 mov ecx,3600
 div rcx
 mov [rsi],rax
 mov rax,rdx
 xor edx,edx
 mov ecx,60
 div rcx
 mov [rsi+8],rax
 mov [rsi+16],rdx
 xor eax,eax
 ret
%ifndef TIME_NATIVE_EMBEDDED
section .note.GNU-stack noalloc noexec nowrite progbits
%endif
