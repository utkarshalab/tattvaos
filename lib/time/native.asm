; Checked native time service used by apps. Initialized once after mono_time_init.
%ifndef TIME_NATIVE_ASM
%define TIME_NATIVE_ASM
%include "lib/time/time.inc"
bits 64
default rel
%ifndef TIME_NATIVE_EMBEDDED
extern mono_get_nanos,rtc_read_epoch
%endif
section .bss
alignb 8
time_native_ready: resq 1
section .text
global time_native_init,time_read_monotonic,time_read_realtime
; Boot owner calls once after the TSC/monotonic service is calibrated.
time_native_init:
 mov qword [time_native_ready],1
 xor eax,eax
 ret
; (out ns) -> 0 / -1 bad pointer / -3 not initialized.
time_read_monotonic:
 test rdi,rdi
 jz .invalid
 cmp qword [time_native_ready],1
 jne .unavailable
 push rbx
 mov rbx,rdi
 call mono_get_nanos
 mov [rbx],rax
 xor eax,eax
 pop rbx
 ret
.invalid: mov rax,-1
 ret
.unavailable: mov rax,-3
 ret
; (out timespec_t) -> 0 / -1 bad pointer / -3 unavailable/unstable RTC.
time_read_realtime:
 test rdi,rdi
 jz .invalid
 cmp qword [time_native_ready],1
 jne .unavailable
 jmp rtc_read_epoch
.invalid: mov rax,-1
 ret
.unavailable: mov rax,-3
 ret
%ifndef TIME_NATIVE_EMBEDDED
section .note.GNU-stack noalloc noexec nowrite progbits
%endif
%endif
