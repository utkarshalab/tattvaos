%include "apps/clock/inc/clock.inc"
bits 64
default rel
%ifndef TIME_NATIVE_EMBEDDED
extern time_read_monotonic,time_read_realtime,uclock_read,cal_civil_from_epoch
%endif
%ifdef TIME_NATIVE_EMBEDDED
section .rodata
%else
section .data.rel.ro
%endif
global uclock_native_sources
uclock_native_sources: dq time_read_monotonic,time_read_realtime
section .text
global uclock_read_native,uclock_local_now
; (out sample) -> status, real lib/time defaults, no caller callbacks required.
uclock_read_native:
 mov rsi,rdi
 lea rdi,[uclock_native_sources]
 jmp uclock_read
; (UTC offset seconds,out civil date) -> status via lib/time + lib/cal.
uclock_local_now:
 push rbx
 push r12
 sub rsp,24
 mov rbx,rdi
 mov r12,rsi
 test rsi,rsi
 jz .invalid
 cmp rdi,-64800
 jl .invalid
 cmp rdi,64800
 jg .invalid
 mov rdi,rsp
 call time_read_realtime
 test rax,rax
 js .done
 mov rdi,[rsp]
 mov rsi,rbx
 mov rdx,r12
 call cal_civil_from_epoch
 jmp .done
.invalid: mov rax,UCLOCK_INVALID
.done: add rsp,24
 pop r12
 pop rbx
 ret
%ifndef TIME_NATIVE_EMBEDDED
section .note.GNU-stack noalloc noexec nowrite progbits
%endif
