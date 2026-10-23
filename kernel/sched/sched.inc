; =============================================================================
; Utkarsha OS — kernel/sched/sched.inc
; =============================================================================
; Scheduler definitions and hardware timer constants.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef SCHED_INC
%define SCHED_INC

; APIC Timer Vector & Frequency
SCHED_YIELD_VECTOR      equ 0xF7    ; Ring-0 software reschedule trap
SCHED_WAKE_VECTOR       equ 0xF8    ; Scheduler park/unpark wake IPI
APIC_TIMER_VECTOR       equ 0xF9    ; Kernel-owned local APIC timer
APIC_TIMER_DIVISOR      equ 16      ; Divide by 16
SCHED_TIME_SLICE_MS     equ 10      ; 10ms preemption slice limit

; Canonical scheduler trap frame. Scheduler-owned vectors have no hardware
; error code, so their entries push a zero error code and vector before the
; complete GPR set. Every resumable fiber context uses this exact format.
SCHED_FRAME_R15         equ 0
SCHED_FRAME_R14         equ 8
SCHED_FRAME_R13         equ 16
SCHED_FRAME_R12         equ 24
SCHED_FRAME_R11         equ 32
SCHED_FRAME_R10         equ 40
SCHED_FRAME_R9          equ 48
SCHED_FRAME_R8          equ 56
SCHED_FRAME_RBP         equ 64
SCHED_FRAME_RDI         equ 72
SCHED_FRAME_RSI         equ 80
SCHED_FRAME_RDX         equ 88
SCHED_FRAME_RCX         equ 96
SCHED_FRAME_RBX         equ 104
SCHED_FRAME_RAX         equ 112
SCHED_FRAME_VECTOR      equ 120
SCHED_FRAME_ERROR       equ 128
SCHED_FRAME_RIP         equ 136
SCHED_FRAME_CS          equ 144
SCHED_FRAME_RFLAGS      equ 152
SCHED_FRAME_RSP         equ 160
SCHED_FRAME_SS          equ 168
SCHED_FRAME_SIZE        equ 176

SCHED_PERCPU_READY      equ 1

%macro SCHED_PUSH_FRAME 1
    push qword 0
    push qword %1
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push rbp
    push r8
    push r9
    push r10
    push r11
    push r12
    push r13
    push r14
    push r15
%endmacro

%macro SCHED_POP_FRAME 0
    pop r15
    pop r14
    pop r13
    pop r12
    pop r11
    pop r10
    pop r9
    pop r8
    pop rbp
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    add rsp, 16                    ; scheduler vector and synthetic error code
%endmacro

%endif ; SCHED_INC
