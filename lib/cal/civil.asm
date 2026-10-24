%ifndef CAL_CIVIL_ASM
%define CAL_CIVIL_ASM
; Checked Gregorian model; no I/O, global state or allocation.
%include "lib/cal/civil.inc"
bits 64
default rel
%ifndef TIME_NATIVE_EMBEDDED
extern cal_is_leap_year,cal_days_in_month,cal_weekday
%endif
section .text
global cal_civil_validate,cal_civil_to_epoch,cal_civil_from_epoch,cal_civil_month_grid
global cal_civil_add_days,cal_civil_add_months,cal_civil_iso_week
; (date*) -> 0 valid, -1 otherwise. Derived weekday/yearday ignored.
cal_civil_validate:
 push rbx
 mov rbx,rdi
 test rdi,rdi
 jz .bad
 mov rdi,[rbx+cal_civil_date.year]
 cmp rdi,1
 jb .bad
 cmp rdi,9999
 ja .bad
 mov rsi,[rbx+cal_civil_date.month]
 call cal_days_in_month
 test rax,rax
 jz .bad
 cmp qword [rbx+cal_civil_date.day],1
 jb .bad
 cmp [rbx+cal_civil_date.day],rax
 ja .bad
 cmp qword [rbx+cal_civil_date.hour],23
 ja .bad
 cmp qword [rbx+cal_civil_date.minute],59
 ja .bad
 cmp qword [rbx+cal_civil_date.second],59
 ja .bad
 xor eax,eax
 jmp .done
.bad: mov rax,CAL_INVALID
.done: pop rbx
 ret
; rdi year -> days before year, AD 1 = day 0.
before_year:
 lea r8,[rdi-1]
 imul r9,r8,365
 mov rax,r8
 shr rax,2
 add r9,rax
 mov rax,r8
 xor edx,edx
 mov ecx,100
 div rcx
 sub r9,rax
 mov rax,r8
 xor edx,edx
 mov ecx,400
 div rcx
 add rax,r9
 ret
; (date, UTC offset seconds, out signed epoch*) -> status; output atomic.
cal_civil_to_epoch:
 push rbx
 push r12
 push r13
 push r14
 push r15
 mov rbx,rdi
 mov r12,rsi
 mov r13,rdx
 test rdx,rdx
 jz .invalid
 cmp rsi,-64800
 jl .invalid
 cmp rsi,64800
 jg .invalid
 call cal_civil_validate
 test rax,rax
 js .done
 mov rdi,[rbx+cal_civil_date.year]
 call before_year
 mov r14,rax
 mov r15d,1
.month:
 cmp r15,[rbx+cal_civil_date.month]
 jae .day
 mov rdi,[rbx+cal_civil_date.year]
 mov rsi,r15
 call cal_days_in_month
 add r14,rax
 inc r15
 jmp .month
.day:
 add r14,[rbx+cal_civil_date.day]
 dec r14
 sub r14,719162
 imul rax,r14,86400
 imul rcx,[rbx+cal_civil_date.hour],3600
 add rax,rcx
 imul rcx,[rbx+cal_civil_date.minute],60
 add rax,rcx
 add rax,[rbx+cal_civil_date.second]
 sub rax,r12
 mov [r13],rax
 xor eax,eax
 jmp .done
.invalid: mov rax,CAL_INVALID
.done: pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 ret
; (signed epoch, UTC offset seconds, date*) -> status; supports pre-1970 dates.
cal_civil_from_epoch:
 push rbx
 push r12
 push r13
 push r14
 push r15
 sub rsp,cal_civil_date_size
 mov rbx,rdx
 test rdx,rdx
 jz .invalid
 cmp rsi,-64800
 jl .invalid
 cmp rsi,64800
 jg .invalid
 add rdi,rsi
 jo .range
 mov rax,-62135596800
 cmp rdi,rax
 jl .range
 mov rax,253402300799
 cmp rdi,rax
 jg .range
 mov rax,rdi
 cqo
 mov ecx,86400
 idiv rcx
 test rdx,rdx
 jns .positive
 dec rax
 add rdx,86400
.positive:
 add rax,719162
 mov r12,rax
 mov rax,rdx
 xor edx,edx
 mov ecx,3600
 div rcx
 mov [rsp+cal_civil_date.hour],rax
 mov rax,rdx
 xor edx,edx
 mov ecx,60
 div rcx
 mov [rsp+cal_civil_date.minute],rax
 mov [rsp+cal_civil_date.second],rdx
 ; Binary search the bounded 1..9999 year range.
 mov r13d,1
 mov r14d,10000
.search:
 lea r15,[r13+r14]
 shr r15,1
 cmp r15,r13
 je .year
 mov rdi,r15
 call before_year
 cmp rax,r12
 ja .lower
 mov r13,r15
 jmp .search
.lower: mov r14,r15
 jmp .search
.year:
 mov [rsp+cal_civil_date.year],r13
 mov rdi,r13
 call before_year
 sub r12,rax
 mov [rsp+cal_civil_date.yearday],r12
 mov r14d,1
.month:
 mov rdi,r13
 mov rsi,r14
 call cal_days_in_month
 cmp r12,rax
 jb .found
 sub r12,rax
 inc r14
 jmp .month
.found:
 mov [rsp+cal_civil_date.month],r14
 inc r12
 mov [rsp+cal_civil_date.day],r12
 mov rdi,r13
 mov rsi,r14
 mov rdx,r12
 call cal_weekday
 mov [rsp+cal_civil_date.weekday],rax
 mov rsi,rsp
 mov rdi,rbx
 mov ecx,cal_civil_date_size/8
 rep movsq
 xor eax,eax
 jmp .done
.invalid: mov rax,CAL_INVALID
 jmp .done
.range: mov rax,CAL_RANGE
.done:
 add rsp,cal_civil_date_size
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 ret
; (year,month,week_start=0 Sun..6 Sat,out month*)
cal_civil_month_grid:
 push rbx
 push r12
 push r13
 push r14
 push r15
 sub rsp,cal_civil_month_size+8
 mov rbx,rcx
 mov r12,rdi
 mov r13,rsi
 mov r14,rdx
 test rcx,rcx
 jz .invalid
 cmp rdi,1
 jb .invalid
 cmp rdi,9999
 ja .invalid
 cmp rdx,6
 ja .invalid
 call cal_days_in_month
 test rax,rax
 jz .invalid
 mov r15,rax
 mov [rsp+cal_civil_month.year],r12
 mov [rsp+cal_civil_month.month],r13
 mov [rsp+cal_civil_month.week_start],r14
 mov [rsp+cal_civil_month.days],rax
 mov rdi,r12
 mov rsi,r13
 mov edx,1
 call cal_weekday
 sub rax,r14
 add rax,7
 xor edx,edx
 mov ecx,7
 div rcx
 mov [rsp+cal_civil_month.first],rdx
 xor ecx,ecx
.cells:
 mov rax,rcx
 sub rax,rdx
 inc rax
 cmp rax,r15
 jbe .store
 xor eax,eax
.store:
 mov [rsp+cal_civil_month.cells+rcx*8],rax
 inc ecx
 cmp ecx,42
 jb .cells
 mov rsi,rsp
 mov rdi,rbx
 mov ecx,cal_civil_month_size/8
 rep movsq
 xor eax,eax
 jmp .done
.invalid: mov rax,CAL_INVALID
.done: add rsp,cal_civil_month_size+8
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 ret
; (date, signed days, out date); aliases supported, time-of-day retained.
cal_civil_add_days:
 push rbx
 push r12
 push r13
 sub rsp,16
 mov rbx,rsi
 mov r12,rdx
 xor esi,esi
 mov rdx,rsp
 call cal_civil_to_epoch
 test rax,rax
 js .done
 imul rbx,rbx,86400
 jo .range
 add rbx,[rsp]
 jo .range
 mov rdi,rbx
 xor esi,esi
 mov rdx,r12
 call cal_civil_from_epoch
 jmp .done
.range: mov rax,CAL_RANGE
.done: add rsp,16
 pop r13
 pop r12
 pop rbx
 ret
; (date,signed months,out date); clamp day to target month's last day.
cal_civil_add_months:
 push rbx
 push r12
 push r13
 sub rsp,cal_civil_date_size+16
 mov rbx,rdi
 mov r12,rsi
 mov r13,rdx
 test rdx,rdx
 jz .invalid
 call cal_civil_validate
 test rax,rax
 js .done
 mov rdi,rsp
 mov rsi,rbx
 mov ecx,cal_civil_date_size/8
 rep movsq
 mov rax,[rsp+cal_civil_date.year]
 dec rax
 imul rax,12
 add rax,[rsp+cal_civil_date.month]
 dec rax
 add rax,r12
 jo .range
 cmp rax,0
 jl .range
 cmp rax,119987
 jg .range
 xor edx,edx
 mov ecx,12
 div rcx
 inc rax
 inc rdx
 mov [rsp+cal_civil_date.year],rax
 mov [rsp+cal_civil_date.month],rdx
 mov rdi,rax
 mov rsi,rdx
 call cal_days_in_month
 cmp [rsp+cal_civil_date.day],rax
 jbe .convert
 mov [rsp+cal_civil_date.day],rax
.convert:
 mov rdi,rsp
 xor esi,esi
 lea rdx,[rsp+cal_civil_date_size]
 call cal_civil_to_epoch
 test rax,rax
 js .done
 mov rdi,[rsp+cal_civil_date_size]
 xor esi,esi
 mov rdx,r13
 call cal_civil_from_epoch
 jmp .done
.invalid: mov rax,CAL_INVALID
 jmp .done
.range: mov rax,CAL_RANGE
.done: add rsp,cal_civil_date_size+16
 pop r13
 pop r12
 pop rbx
 ret
; (date,out qwords[iso_year,week,weekday Monday=1..Sunday=7])
cal_civil_iso_week:
 push rbx
 push r12
 push r13
 sub rsp,cal_civil_date_size+32
 mov r12,rsi
 test rsi,rsi
 jz .invalid
 xor esi,esi
 lea rdx,[rsp+cal_civil_date_size]
 call cal_civil_to_epoch
 test rax,rax
 js .done
 mov rdi,[rsp+cal_civil_date_size]
 xor esi,esi
 mov rdx,rsp
 call cal_civil_from_epoch
 mov rax,[rsp+cal_civil_date.weekday]
 add rax,6
 xor edx,edx
 mov ecx,7
 div rcx
 inc rdx
 mov r13,rdx
 mov eax,4
 sub rax,rdx
 imul rax,86400
 add rax,[rsp+cal_civil_date_size]
 ; ISO week years can be 0 or 10000 at the supported date boundaries.
 ; Determine Thursday's year by comparison with the current year extents.
 mov rbx,rax
 mov rdi,[rsp+cal_civil_date.year]
 call before_year
 sub rax,719162
 imul rax,86400
 cmp rbx,rax
 jge .not_previous
 dec qword [rsp+cal_civil_date.year]
.not_previous:
 mov rdi,[rsp+cal_civil_date.year]
 inc rdi
 call before_year
 sub rax,719162
 imul rax,86400
 cmp rbx,rax
 jl .iso_year
 inc qword [rsp+cal_civil_date.year]
.iso_year:
 mov rdi,[rsp+cal_civil_date.year]
 call before_year
 sub rax,719162
 imul rax,86400
 sub rbx,rax
 mov rax,rbx
 xor edx,edx
 mov ecx,604800
 div rcx
 inc rax
 mov rcx,[rsp+cal_civil_date.year]
 mov [r12],rcx
 mov [r12+8],rax
 mov [r12+16],r13
 xor eax,eax
 jmp .done
.invalid: mov rax,CAL_INVALID
.done: add rsp,cal_civil_date_size+32
 pop r13
 pop r12
 pop rbx
 ret
%ifndef TIME_NATIVE_EMBEDDED
section .note.GNU-stack noalloc noexec nowrite progbits
%endif

%endif
