; UTM Kernel - Flight Recorder
; Pure Assembly Implementation

%ifndef _UTM_FLIGHT_REC_ASM_
%define _UTM_ENTERPRISE_FLIGHT_REC_ASM_

%include "constants.inc"
%include "structures.inc"
%include "syscalls.inc"

%define FLIGHT_RECORD_SIZE 4096
%define MAX_FLIGHT_RECORDS 1000

section .rodata
utm_flight_rec_lock dq 0

section .bss
align 4096
global utm_flight_recorder
utm_flight_recorder:
    .header           resb FLIGHT_HEADER_SIZE
    .buffer           resb MAX_FLIGHT_RECORDS * FLIGHT_RECORD_SIZE

section .text

global utm_flight_rec_init
global utm_flight_rec_start
global utm_flight_rec_stop
global utm_flight_rec_record
global utm_flight_rec_read
global utm_flight_rec_status

extern utm_get_monotonic_ns
extern utm_spin_lock_acquire
extern utm_spin_lock_release

utm_flight_rec_init:
    mov rdi, utm_flight_recorder
    mov rcx, (FLIGHT_HEADER_SIZE + MAX_FLIGHT_RECORDS * FLIGHT_RECORD_SIZE) / 8
    xor rax, rax
    rep stosq
    
    mov rax, FLIGHT_MAGIC
    mov [utm_flight_recorder + FlightRecorderHeader.magic], rax
    mov dword [utm_flight_recorder + FlightRecorderHeader.version], 1
    mov dword [utm_flight_recorder + FlightRecorderHeader.record_size], FLIGHT_RECORD_SIZE
    mov qword [utm_flight_recorder + FlightRecorderHeader.capacity], MAX_FLIGHT_RECORDS
    ret

utm_flight_rec_start:
    call utm_spin_lock_acquire
    
    call utm_get_monotonic_ns
    mov [utm_flight_recorder + FlightRecorderHeader.start_time_ns], rax
    mov qword [utm_flight_recorder + FlightRecorderHeader.end_time_ns], 0
    mov qword [utm_flight_recorder + FlightRecorderHeader.head], 0
    mov qword [utm_flight_recorder + FlightRecorderHeader.tail], 0
    mov qword [utm_flight_recorder + FlightRecorderHeader.count], 0
    mov dword [utm_flight_recorder + FlightRecorderHeader.trigger_reason], edi
    mov qword [utm_flight_recorder + FlightRecorderHeader.flags], FLIGHT_FLAG_ACTIVE
    
    call utm_spin_lock_release
    ret

utm_flight_rec_stop:
    call utm_spin_lock_acquire
    
    call utm_get_monotonic_ns
    mov [utm_flight_recorder + FlightRecorderHeader.end_time_ns], rax
    and qword [utm_flight_recorder + FlightRecorderHeader.flags], ~FLIGHT_FLAG_ACTIVE
    
    call utm_spin_lock_release
    ret

utm_flight_rec_record:
    test qword [utm_flight_recorder + FlightRecorderHeader.flags], FLIGHT_FLAG_ACTIVE
    jz .done
    
    call utm_spin_lock_acquire
    
    mov rax, [utm_flight_recorder + FlightRecorderHeader.head]
    mov rcx, [utm_flight_recorder + FlightRecorderHeader.capacity]
    mov r8, [utm_flight_recorder + FlightRecorderHeader.record_size]
    
    mul r8
    add rax, utm_flight_recorder + FLIGHT_HEADER_SIZE
    mov r9, rax
    
    mov rcx, SYS_SAMPLE_SIZE / 8
    rep movsq
    
    mov [r9 + SYS_SAMPLE_SIZE], edx
    
    lea r9, [r9 + SYS_SAMPLE_SIZE + 4]
    mov rcx, rdx
    mov r8, CONTAINER_SAMPLE_SIZE / 8
.proc_loop:
    push rcx
    mov rcx, r8
    rep movsq
    pop rcx
    loop .proc_loop
    
    inc qword [utm_flight_recorder + FlightRecorderHeader.head]
    mov rax, [utm_flight_recorder + FlightRecorderHeader.head]
    cmp rax, [utm_flight_recorder + FlightRecorderHeader.capacity]
    jne .no_wrap
    mov qword [utm_flight_recorder + FlightRecorderHeader.head], 0
    or qword [utm_flight_recorder + FlightRecorderHeader.flags], FLIGHT_FLAG_WRAPPED
.no_wrap:
    
    mov rax, [utm_flight_recorder + FlightRecorderHeader.count]
    cmp rax, [utm_flight_recorder + FlightRecorderHeader.capacity]
    jae .full
    inc qword [utm_flight_recorder + FlightRecorderHeader.count]
    jmp .done_lock
.full:
    inc qword [utm_flight_recorder + FlightRecorderHeader.tail]
    mov rax, [utm_flight_recorder + FlightRecorderHeader.tail]
    cmp rax, [utm_flight_recorder + FlightRecorderHeader.capacity]
    jne .done_lock
    mov qword [utm_flight_recorder + FlightRecorderHeader.tail], 0
    inc qword [utm_flight_recorder + FlightRecorderHeader.overruns]
    
.done_lock:
    call utm_spin_lock_release
.done:
    ret

utm_flight_rec_read:
    call utm_spin_lock_acquire
    
    mov rax, [utm_flight_recorder + FlightRecorderHeader.tail]
    add rax, rdi
    cmp rax, [utm_flight_recorder + FlightRecorderHeader.capacity]
    jl .no_wrap_read
    sub rax, [utm_flight_recorder + FlightRecorderHeader.capacity]
.no_wrap_read:
    
    mov rcx, [utm_flight_recorder + FlightRecorderHeader.count]
    sub rcx, rdi
    cmp rcx, rsi
    jg .limit_ok
    mov rcx, rsi
.limit_ok:
    
    mov r8, [utm_flight_recorder + FlightRecorderHeader.record_size]
    mul r8
    add rax, utm_flight_recorder + FLIGHT_HEADER_SIZE
    mov r9, rax
    mov rdi, rdx
    
    mov r10, rcx
.read_loop:
    push rcx
    mov rcx, r8
    shr rcx, 3
    rep movsq
    pop rcx
    loop .read_loop
    
    mov rax, r10
    call utm_spin_lock_release
    ret

utm_flight_rec_status:
    mov rsi, utm_flight_recorder
    mov rcx, FLIGHT_HEADER_SIZE / 8
    rep movsq
    ret

%endif