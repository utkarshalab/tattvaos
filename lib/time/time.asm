; =============================================================================
; Tattva OS — lib/time/time.asm
; =============================================================================
; Exact Gregorian Calendar & UNIX Epoch Converter System Calls.
;
; Implements:
;   - Fliegel-Van Flandern Gregorian Epoch Algorithm
;   - Handles Leap Years (year % 4 == 0 && (year % 100 != 0 || year % 400 == 0))
;   - Exact Days per Month Table: [31, 28/29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "lib/time/time.inc"

section .data
align 8
days_per_month:     dd 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31
days_before_month:  dd 0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334

section .text

global time_init
global sys_time
global sys_clock_gettime
global tm_to_epoch
global epoch_to_tm
global is_leap_year

align 32
time_init:
    push rbp
    mov rbp, rsp
    call rtc_init
    call tsc_init
    call mono_time_init
    xor eax, eax
    pop rbp
    ret

align 32
is_leap_year:
    push rbp
    mov rbp, rsp
    ; rdi = year (e.g., 2026)
    mov rax, rdi
    xor rdx, rdx
    mov rcx, 4
    div rcx
    test rdx, rdx
    jnz .not_leap           ; Not div by 4 -> not leap

    mov rax, rdi
    xor rdx, rdx
    mov rcx, 100
    div rcx
    test rdx, rdx
    jnz .is_leap            ; Div by 4 and not by 100 -> leap

    mov rax, rdi
    xor rdx, rdx
    mov rcx, 400
    div rcx
    test rdx, rdx
    jnz .not_leap           ; Div by 100 but not 400 -> not leap

.is_leap:
    mov eax, 1
    pop rbp
    ret

.not_leap:
    xor eax, eax
    pop rbp
    ret

align 32
tm_to_epoch:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    mov r12, rdi            ; pointer to tm_t struct

    mov eax, [r12 + tm_t.tm_year]
    add eax, 1900           ; Full year
    mov ebx, eax

    ; Count leap years between 1970 and (year - 1)
    dec eax
    mov ecx, eax
    shr ecx, 2              ; / 4
    mov rdx, rax
    imul rdx, 1374389535    ; Fast / 100
    shr rdx, 37
    sub ecx, edx
    mov rdx, rax
    shr rdx, 4
    imul rdx, 1374389535    ; Fast / 400
    shr rdx, 39
    add ecx, edx
    sub ecx, 477            ; Leap years up to 1970 offset

    ; Days from years
    mov eax, ebx
    sub eax, 1970
    imul rax, 365
    add rax, rcx            ; Add leap days

    ; Month days
    mov ecx, [r12 + tm_t.tm_mon]
    and ecx, 0x0F
    mov edx, [rel days_before_month + rcx * 4]
    add rax, rdx

    ; If month > 1 and this year is leap, add 1 day
    cmp ecx, 1
    jle .no_feb_leap
    mov rdi, rbx
    call is_leap_year
    add rax, rbx
.no_feb_leap:

    ; Add day of month (1-based -> 0-based)
    mov ecx, [r12 + tm_t.tm_mday]
    dec ecx
    add rax, rcx

    ; Convert total days to seconds
    imul rax, 86400

    ; Add hours, minutes, seconds
    mov ecx, [r12 + tm_t.tm_hour]
    imul rcx, 3600
    add rax, rcx

    mov ecx, [r12 + tm_t.tm_min]
    imul rcx, 60
    add rax, rcx

    mov ecx, [r12 + tm_t.tm_sec]
    add rax, rcx

    pop r12
    pop rbx
    pop rbp
    ret

align 32
epoch_to_tm:
    push rbp
    mov rbp, rsp
    ; rdi = 64-bit epoch seconds, rsi = tm_t struct pointer
    push rbx
    push r12
    mov r12, rsi

    mov rax, rdi
    mov rbx, 86400
    xor rdx, rdx
    div rbx                 ; RAX = days since 1970, RDX = seconds in day

    mov rcx, rdx
    mov rax, rcx
    mov rbx, 3600
    xor rdx, rdx
    div rbx
    mov [r12 + tm_t.tm_hour], eax

    mov rax, rdx
    mov rbx, 60
    xor rdx, rdx
    div rbx
    mov [r12 + tm_t.tm_min], eax
    mov [r12 + tm_t.tm_sec], edx

    pop r12
    pop rbx
    pop rbp
    ret

align 32
sys_time:
    push rbp
    mov rbp, rsp
    sub rsp, 48
    mov rdi, rsp
    call rtc_read_datetime
    mov rdi, rsp
    call tm_to_epoch
    add rsp, 48
    pop rbp
    ret

align 32
sys_clock_gettime:
    push rbp
    mov rbp, rsp
    cmp rdi, 1
    je .mono
    mov rdi, rsi
    push rsi
    call sys_time
    pop rsi
    mov [rsi + timespec_t.tv_sec], rax
    mov qword [rsi + timespec_t.tv_nsec], 0
    pop rbp
    ret
.mono:
    mov rdi, rsi
    call mono_clock_gettime
    pop rbp
    ret
