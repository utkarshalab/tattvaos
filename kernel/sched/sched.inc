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
APIC_TIMER_VECTOR       equ 32      ; IRQ0 mapped to IDT vector 32
APIC_TIMER_DIVISOR      equ 16      ; Divide by 16
SCHED_TIME_SLICE_MS     equ 10      ; 10ms preemption slice limit

%endif ; SCHED_INC
