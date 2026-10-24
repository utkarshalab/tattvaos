%include "apps/calender/inc/calender.inc"
bits 64
default rel
%ifndef TIME_NATIVE_EMBEDDED
extern time_read_realtime,ucal_from_epoch,ucal_month_grid
%endif
section .text
global ucal_now,ucal_month_now
; (UTC offset seconds,out date) -> status. Real checked lib/time UTC source.
ucal_now:
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
 js .unavailable
 mov rdi,[rsp]
 mov rsi,rbx
 mov rdx,r12
 call ucal_from_epoch
 jmp .done
.unavailable: mov rax,UCAL_UNAVAILABLE
 jmp .done
.invalid: mov rax,UCAL_INVALID
.done: add rsp,24
 pop r12
 pop rbx
 ret
; (UTC offset,week start,out month grid)
ucal_month_now:
 push rbx
 push r12
 sub rsp,ucal_date_size+8
 mov rbx,rsi
 mov r12,rdx
 test rdx,rdx
 jz .invalid
 cmp rsi,6
 ja .invalid
 mov rsi,rsp
 call ucal_now
 test rax,rax
 js .done
 mov rdi,[rsp+ucal_date.year]
 mov rsi,[rsp+ucal_date.month]
 mov rdx,rbx
 mov rcx,r12
 call ucal_month_grid
 jmp .done
.invalid: mov rax,UCAL_INVALID
.done: add rsp,ucal_date_size+8
 pop r12
 pop rbx
 ret
%ifndef TIME_NATIVE_EMBEDDED
section .note.GNU-stack noalloc noexec nowrite progbits
%endif
