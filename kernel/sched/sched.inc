; =============================================================================
; Tattva OS — kernel/sched/sched.inc
; =============================================================================
; Scheduler definitions and hardware timer constants.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef SCHED_INC
%define SCHED_INC

; APIC Timer Vector & Frequency
SCHED_WAKE_VECTOR       equ 0xF8    ; Scheduler park/unpark wake IPI
APIC_TIMER_VECTOR       equ 0xF9    ; Kernel-owned local APIC timer
APIC_TIMER_DIVISOR      equ 16      ; Divide by 16
SCHED_TIME_SLICE_MS     equ 10      ; 10ms preemption slice limit

%endif ; SCHED_INC
