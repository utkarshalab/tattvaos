; Host-only fake hardware boundaries. Production service/RTC/mono code is linked.
bits 64
default rel
section .bss
global time_test_cmos,time_test_ticks,time_test_reads,time_test_unstable,time_test_stuck
time_test_cmos: resb 128
time_test_ticks: resq 1
time_test_reads: resq 1
time_test_unstable: resq 1
time_test_stuck: resq 1
section .text
global tsc_read,tsc_elapsed_nanos,time_test_cmos_read
tsc_read:
 mov rax,[time_test_ticks]
 ret
tsc_elapsed_nanos:
 mov rax,rsi
 sub rax,rdi
 ret
time_test_cmos_read:
 inc qword [time_test_reads]
 cmp edi,0x0a
 jne .value
 cmp qword [time_test_stuck],0
 je .value
 mov eax,0x80
 ret
.value:
 lea rax,[time_test_cmos]
 movzx eax,byte [rax+rdi]
 cmp qword [time_test_unstable],0
 je .done
 cmp edi,0
 jne .done
 ; Change seconds every complete snapshot so stable comparison must reject it.
 xor byte [time_test_cmos],1
.done: ret
section .note.GNU-stack noalloc noexec nowrite progbits
