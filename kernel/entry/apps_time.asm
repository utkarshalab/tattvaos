; Native app/date/time wiring. No Canvas/UI dependency.
%include "apps/calender/src/date.asm"
%include "apps/calender/src/now.asm"
%include "apps/clock/src/clock.asm"
%include "apps/clock/src/native.asm"
section .bss
alignb 8
apps_time_sample: resb uclock_sample_size
apps_time_local: resb ucal_date_size
apps_time_month: resb ucal_month_size
section .rodata
apps_time_ok: db '[apps/time] native clock/calendar: PASS utc=',0
apps_time_local_label: db ' local=',0
apps_time_separator: db '/',0
apps_time_space: db ' ',0
apps_time_colon: db ':',0
apps_time_newline: db 13,10,0
apps_time_unavailable: db '[apps/time] native clock/calendar: unavailable',13,10,0
section .text
kernel_apps_time_probe:
 push rbx
 lea rdi,[apps_time_sample]
 call uclock_read_native
 test rax,rax
 js .unavailable
 mov edi,20700
 lea rsi,[apps_time_local]
 call ucal_now
 test rax,rax
 js .unavailable
 mov edi,20700
 lea rsi,[apps_time_local]
 call uclock_local_now
 test rax,rax
 js .unavailable
 mov edi,20700
 mov esi,1
 lea rdx,[apps_time_month]
 call ucal_month_now
 test rax,rax
 js .unavailable
 lea rsi,[apps_time_ok]
 call uart_print_str
 mov rax,[apps_time_sample+uclock_sample.utc_seconds]
 call uart_print_hex64
 lea rsi,[apps_time_local_label]
 call uart_print_str
 mov eax,[apps_time_local+ucal_date.year]
 call uart_print_dec
 lea rsi,[apps_time_separator]
 call uart_print_str
 mov eax,[apps_time_local+ucal_date.month]
 call uart_print_dec
 lea rsi,[apps_time_separator]
 call uart_print_str
 mov eax,[apps_time_local+ucal_date.day]
 call uart_print_dec
 lea rsi,[apps_time_space]
 call uart_print_str
 mov eax,[apps_time_local+ucal_date.hour]
 call uart_print_dec
 lea rsi,[apps_time_colon]
 call uart_print_str
 mov eax,[apps_time_local+ucal_date.minute]
 call uart_print_dec
 lea rsi,[apps_time_newline]
 call uart_print_str
 pop rbx
 ret
.unavailable:
 lea rsi,[apps_time_unavailable]
 call uart_print_str
 pop rbx
 ret
