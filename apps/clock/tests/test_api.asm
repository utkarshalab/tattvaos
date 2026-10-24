; Native assembly API integration. Linux syscalls occur only in this test runner.
%include "apps/calender/inc/api.inc"
%include "apps/clock/inc/api.inc"
bits 64
default rel
%macro OK 0
 test rax,rax
 jnz fail
%endmacro
%macro EQ 2
 cmp %1,%2
 jne fail
%endmacro
section .data
sources: dq monotonic,realtime
date: dq 2024,1,31,0,0,0,0,0
event: dq 0,0,3600,0
 db 'Meeting',0
 times 120 db 0
alarm: dq 0,10,10,1
section .rodata
success: db 'Calendar/clock native assembly API: PASS',10
success_len: equ $-success
failure: db 'Calendar/clock native assembly API: FAIL',10
failure_len: equ $-failure
section .bss
sample: resb uclock_sample_size
local_date: resb ucal_date_size
shifted: resb ucal_date_size
view: resb ucal_month_size
week: resq 3
epoch: resq 1
events: resb ucal_store_size
id: resq 1
total: resq 1
ids: resq 1
watch: resb uclock_stopwatch_size
timer: resb uclock_countdown_size
elapsed: resq 1
parts: resq 4
alarms: resb uclock_alarms_size
notice: resb uclock_notification_size
section .text
global _start
_start:
 ; Linux entry stack is 16-byte aligned. Seed/check preserved registers.
 mov ebx,0x1234
 mov r12d,0x2345
 mov r13d,0x3456
 mov r14d,0x4567
 mov r15d,0x5678
 lea rdi,[sources]
 lea rsi,[sample]
 call uclock_read
 OK
 EQ qword [sample+uclock_sample.nanoseconds],42
 xor edi,edi
 mov esi,20700
 lea rdx,[local_date]
 call ucal_from_epoch
 OK
 EQ qword [local_date+ucal_date.year],1970
 EQ qword [local_date+ucal_date.hour],5
 EQ qword [local_date+ucal_date.minute],45
 lea rdi,[local_date]
 mov esi,20700
 lea rdx,[epoch]
 call ucal_to_epoch
 OK
 EQ qword [epoch],0
 mov edi,2024
 mov esi,2
 mov edx,1
 lea rcx,[view]
 call ucal_month_grid
 OK
 EQ qword [view+ucal_month.days],29
 EQ qword [view+ucal_month.first],3
 lea rdi,[date]
 mov esi,1
 lea rdx,[shifted]
 call ucal_add_months
 OK
 EQ qword [shifted+ucal_date.day],29
 lea rdi,[shifted]
 mov esi,1
 mov rdx,rdi
 call ucal_add_days
 OK
 EQ qword [shifted+ucal_date.month],3
 lea rdi,[shifted]
 lea rsi,[week]
 call ucal_iso_week
 OK
 EQ qword [week+8],9
 lea rdi,[events]
 call ucal_store_init
 OK
 lea rdi,[events]
 lea rsi,[event]
 lea rdx,[id]
 call ucal_event_put
 OK
 lea rdi,[events]
 xor esi,esi
 mov edx,1
 lea rcx,[ids]
 mov r8d,1
 lea r9,[total]
 call ucal_event_query
 EQ rax,1
 EQ qword [total],1
 lea rdi,[events]
 mov rsi,[id]
 lea rdx,[event]
 call ucal_event_get
 OK
 EQ qword [event+ucal_event.end],3600
 lea rdi,[events]
 mov rsi,[id]
 call ucal_event_delete
 OK
 lea rdi,[watch]
 call uclock_stopwatch_init
 OK
 lea rdi,[watch]
 xor esi,esi
 call uclock_stopwatch_start
 OK
 lea rdi,[watch]
 mov esi,1000
 lea rdx,[elapsed]
 call uclock_stopwatch_lap
 OK
 EQ qword [elapsed],1000
 lea rdi,[watch]
 mov esi,2000
 call uclock_stopwatch_pause
 OK
 lea rdi,[watch]
 mov esi,5000
 call uclock_stopwatch_start
 OK
 lea rdi,[watch]
 mov esi,6000
 lea rdx,[elapsed]
 call uclock_stopwatch_read
 OK
 EQ qword [elapsed],3000
 lea rdi,[timer]
 call uclock_countdown_init
 OK
 lea rdi,[timer]
 mov esi,100
 mov edx,1000
 call uclock_countdown_start
 OK
 lea rdi,[timer]
 mov esi,1040
 call uclock_countdown_pause
 OK
 EQ qword [timer+uclock_countdown.remaining],60
 lea rdi,[timer]
 mov esi,2000
 call uclock_countdown_resume
 OK
 lea rdi,[timer]
 mov esi,2060
 lea rdx,[elapsed]
 call uclock_countdown_poll
 EQ rax,1
 EQ qword [elapsed],0
 lea rdi,[timer]
 mov esi,2061
 lea rdx,[elapsed]
 call uclock_countdown_poll
 OK
 mov rdi,3661000000042
 lea rsi,[parts]
 call uclock_duration_parts
 OK
 EQ qword [parts],1
 EQ qword [parts+8],1
 EQ qword [parts+16],1
 EQ qword [parts+24],42
 lea rdi,[alarms]
 call uclock_alarms_init
 OK
 lea rdi,[alarms]
 lea rsi,[alarm]
 lea rdx,[id]
 call uclock_alarm_put
 OK
 lea rdi,[alarms]
 mov esi,35
 lea rdx,[notice]
 mov ecx,1
 call uclock_alarm_poll
 EQ rax,1
 EQ qword [notice+uclock_notification.missed],2
 lea rdi,[alarms]
 mov rsi,[id]
 lea rdx,[alarm]
 call uclock_alarm_get
 OK
 EQ qword [alarm+uclock_alarm.due],40
 lea rdi,[alarms]
 mov rsi,[id]
 call uclock_alarm_delete
 OK
 EQ rbx,0x1234
 EQ r12,0x2345
 EQ r13,0x3456
 EQ r14,0x4567
 EQ r15,0x5678
 mov eax,1
 mov edi,1
 lea rsi,[success]
 mov edx,success_len
 syscall
 xor edi,edi
 mov eax,60
 syscall
monotonic:
 mov rax,rsp
 and eax,15
 EQ eax,8
 mov qword [rdi],1000
 xor eax,eax
 ret
realtime:
 mov rax,rsp
 and eax,15
 EQ eax,8
 mov qword [rdi],0
 mov qword [rdi+8],42
 xor eax,eax
 ret
fail:
 mov eax,1
 mov edi,2
 lea rsi,[failure]
 mov edx,failure_len
 syscall
 mov edi,1
 mov eax,60
 syscall
section .note.GNU-stack noalloc noexec nowrite progbits
