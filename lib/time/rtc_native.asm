; Stable, bounded CMOS UTC reader. Does not change RTC encoding/hour mode.
%ifndef RTC_NATIVE_ASM
%define RTC_NATIVE_ASM
%include "lib/cal/civil.inc"
%include "lib/time/time.inc"
bits 64
default rel
%ifndef TIME_NATIVE_EMBEDDED
extern cal_civil_to_epoch
%endif
%ifdef TIME_NATIVE_TEST
extern time_test_cmos_read
%endif
section .bss
alignb 8
rtc_native_lock: resq 1
section .text
global rtc_read_epoch
; (out timespec) -> 0 / -1 null / -3 failed/stuck/invalid RTC. Atomic output.
rtc_read_epoch:
 push rbx
 push r12
 push r13
 push r14
 push r15
 sub rsp,112
 mov r12,rdi
 test rdi,rdi
 jz .invalid
%ifndef TIME_NATIVE_TEST
 pushfq
 pop r15
 cli
%endif
 mov ecx,100000
.acquire:
 lock bts qword [rtc_native_lock],0
 jnc .locked
 pause
 dec ecx
 jnz .acquire
 mov rax,-3
 jmp .unavailable_unlocked
.locked:
 mov r13d,8
.retry:
 ; Read two complete rtc_native_snapshots, rejecting UIP and any mode/date change.
 lea rdi,[rsp+64]
 call rtc_native_snapshot
 test rax,rax
 js .again
 lea rdi,[rsp+80]
 call rtc_native_snapshot
 test rax,rax
 js .again
 mov rax,[rsp+64]
 cmp rax,[rsp+80]
 je .stable
.again:
 dec r13d
 jnz .retry
 jmp .unavailable
.stable:
 ; bytes: sec,min,hour,day,month,year,century,status B.
 mov r14b,[rsp+71]
 lea rdi,[rsp]
 xor eax,eax
 mov ecx,8
 rep stosq
 movzx eax,byte [rsp+64]
 call rtc_native_decode
 test rax,rax
 js .unavailable
 mov [rsp+cal_civil_date.second],rax
 movzx eax,byte [rsp+65]
 call rtc_native_decode
 test rax,rax
 js .unavailable
 mov [rsp+cal_civil_date.minute],rax
 movzx ebx,byte [rsp+66]
 mov eax,ebx
 and eax,0x7f
 call rtc_native_decode
 test rax,rax
 js .unavailable
 test r14b,2
 jnz .hour24
 cmp rax,1
 jb .unavailable
 cmp rax,12
 ja .unavailable
 cmp rax,12
 jne .pm
 xor eax,eax
.pm:
 test bl,0x80
 jz .hour
 add eax,12
 jmp .hour
.hour24:
 test bl,0x80
 jnz .unavailable
.hour:
 mov [rsp+cal_civil_date.hour],rax
 movzx eax,byte [rsp+67]
 call rtc_native_decode
 test rax,rax
 js .unavailable
 mov [rsp+cal_civil_date.day],rax
 movzx eax,byte [rsp+68]
 call rtc_native_decode
 test rax,rax
 js .unavailable
 mov [rsp+cal_civil_date.month],rax
 movzx eax,byte [rsp+69]
 call rtc_native_decode
 test rax,rax
 js .unavailable
 cmp rax,99
 ja .unavailable
 mov rbx,rax
 movzx eax,byte [rsp+70]
 ; Century register is optional. 0/0xff means absent: explicit 2000..2099.
 test eax,eax
 jz .century_absent
 cmp eax,255
 je .century_absent
 call rtc_native_decode
 test rax,rax
 js .unavailable
 cmp rax,99
 ja .unavailable
 imul rax,100
 jmp .year
.century_absent: mov eax,2000
.year:
 add rax,rbx
 mov [rsp+cal_civil_date.year],rax
 mov rdi,rsp
 xor esi,esi
 lea rdx,[rsp+96]
 call cal_civil_to_epoch
 test rax,rax
 js .unavailable
 mov rax,[rsp+96]
 mov [r12+timespec_t.tv_sec],rax
 mov qword [r12+timespec_t.tv_nsec],0
 xor eax,eax
 jmp .unlock
.invalid:
 mov rax,-1
 jmp .done
.unavailable:
 mov rax,-3
.unlock:
 mov qword [rtc_native_lock],0
.unavailable_unlocked:
%ifndef TIME_NATIVE_TEST
 push r15
 popfq
%endif
.done:
 add rsp,112
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 ret
; EAX raw field -> rtc_native_decoded value / -1. Status B bit 2 selects binary.
rtc_native_decode:
 test r14b,4
 jnz .done
 mov edx,eax
 and edx,15
 cmp edx,9
 ja .bad
 shr eax,4
 cmp eax,9
 ja .bad
 imul eax,10
 add eax,edx
.done: ret
.bad: mov rax,-1
 ret
; (8-byte buffer) -> 0 or -1; at most 4096 UIP probes.
rtc_native_snapshot:
 push rbx
 push r12
 push r13
 mov rbx,rdi
 mov edi,0x0d
 call rtc_native_read_cmos
 test al,0x80
 jz .bad
 mov r12d,4096
.wait:
 mov edi,0x0a
 call rtc_native_read_cmos
 test al,0x80
 jz .ready
 dec r12d
 jnz .wait
 mov rax,-1
 jmp .done
.ready:
 xor r13d,r13d
.loop:
 lea rax,[rtc_native_registers]
 movzx edi,byte [rax+r13]
 call rtc_native_read_cmos
 mov [rbx+r13],al
 inc r13d
 cmp r13d,8
 jb .loop
 mov edi,0x0a
 call rtc_native_read_cmos
 test al,0x80
 jnz .bad
 test byte [rbx+7],0x80        ; SET freezes RTC update: do not report it live.
 jnz .bad
 xor eax,eax
 jmp .done
.bad: mov rax,-1
.done:
 pop r13
 pop r12
 pop rbx
 ret
rtc_native_read_cmos:
%ifdef TIME_NATIVE_TEST
 jmp time_test_cmos_read
%else
 ; NMI stays disabled only across the index/data pair, restored immediately.
 mov eax,edi
 or al,0x80
 out CMOS_ADDR_PORT,al
 in al,CMOS_DATA_PORT
 mov dl,al
 mov eax,edi
 out CMOS_ADDR_PORT,al
 movzx eax,dl
 ret
%endif
section .rodata
rtc_native_registers: db 0,2,4,7,8,9,0x32,0x0b
%ifndef TIME_NATIVE_EMBEDDED
section .note.GNU-stack noalloc noexec nowrite progbits
%endif
%endif
