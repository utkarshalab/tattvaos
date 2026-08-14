%ifndef GUARD_LIB_TIME_MONO_ASM
%define GUARD_LIB_TIME_MONO_ASM
; =============================================================================
; Tattva OS — lib/time/mono.asm
; =============================================================================
; Monotonic High-Resolution System Clock Engine (`CLOCK_MONOTONIC`).
;
; Implements:
;   - Monotonic Nanosecond Counter immune to NTP time jumps or manual clock drift
;   - POSIX `clock_gettime(CLOCK_MONOTONIC, &ts)` System Call Assembly Implementation
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "lib/time/time.inc"

section .data
align 8
mono_base_tsc:      dq 0
mono_base_nsec:     dq 0

section .text

global mono_time_init
global mono_clock_gettime
global mono_get_nanos

align 32
mono_time_init:
    push rbp
    mov rbp, rsp
    call tsc_read
    mov [rel mono_base_tsc], rax
    mov qword [rel mono_base_nsec], 0
    xor eax, eax
    pop rbp
    ret

align 32
mono_clock_gettime:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    mov r12, rdi            ; timespec_t struct pointer

    call tsc_read
    mov rsi, rax
    mov rdi, [rel mono_base_tsc]
    call tsc_elapsed_nanos

    ; RAX = total elapsed nanoseconds
    mov rbx, 1000000000
    xor rdx, rdx
    div rbx                 ; RAX = seconds, RDX = remainder nanoseconds

    mov [r12 + timespec_t.tv_sec], rax
    mov [r12 + timespec_t.tv_nsec], rdx

    pop r12
    pop rbx
    pop rbp
    ret

align 32
mono_get_nanos:
    push rbp
    mov rbp, rsp
    call tsc_read
    mov rsi, rax
    mov rdi, [rel mono_base_tsc]
    call tsc_elapsed_nanos
    pop rbp
    ret

%endif ; GUARD_LIB_TIME_MONO_ASM
