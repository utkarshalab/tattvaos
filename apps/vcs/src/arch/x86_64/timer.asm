; =============================================================================
; File     : src/arch/x86_64/timer.asm
; Project  : Utkarsha VCS (vcs)
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Timer primitives — RDTSC, TSC calibration.
; =============================================================================

%ifndef VCS_ARCH_X86_64_TIMER_ASM
%define VCS_ARCH_X86_64_TIMER_ASM

%include "include/vcs.inc"

bits 64

section .bss
align 16
tsc_freq_hz:  resq 1      ; calibrated TSC frequency

section .text

; -----------------------------------------------------------------------------
; timer_rdtsc — Read Time-Stamp Counter
; Output: rax = TSC value (low), rdx = high
; -----------------------------------------------------------------------------
global timer_rdtsc
timer_rdtsc:
    PROLOGUE_SAVE rbx
    rdtsc
    shl     rdx, 32
    or      rax, rdx
    mov     rbx, rax
    mov     rax, rbx
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; timer_rdtscp — Read TSC with processor ID
; Output: rax = TSC value, rcx = IA32_TSC_AUX
; -----------------------------------------------------------------------------
global timer_rdtscp
timer_rdtscp:
    PROLOGUE_SAVE rbx
    rdtscp
    shl     rdx, 32
    or      rax, rdx
    mov     rbx, rax
    mov     rax, rbx
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; timer_calibrate — Calibrate TSC frequency against PIT/HPET
; Input:  none
; Output: rax = frequency in Hz
; -----------------------------------------------------------------------------
global timer_calibrate
timer_calibrate:
    PROLOGUE_SAVE rbx
    ; TODO: calibrate against PIT channel 0 or HPET
    mov     rax, 3000000000       ; default 3 GHz assumption
    mov     [tsc_freq_hz], rax
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; timer_get_freq — Get calibrated TSC frequency
; Output: rax = frequency in Hz
; -----------------------------------------------------------------------------
global timer_get_freq
timer_get_freq:
    mov     rax, [tsc_freq_hz]
    ret

%endif ; VCS_ARCH_X86_64_TIMER_ASM