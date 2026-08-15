%ifndef GUARD_LIB_TIME_DELAY_ASM
%define GUARD_LIB_TIME_DELAY_ASM
; =============================================================================
; Tattva OS — lib/time/delay.asm
; =============================================================================
; Microsecond & Nanosecond Hardware Spin-Wait Delay Routines.
;
; Implements:
;   - Calibrated `udelay(microseconds)` & `ndelay(nanoseconds)` Spin-Wait Loops
;   - CPU power-saving `PAUSE` instruction loop to optimize SMT hyperthreads
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "lib/time/time.inc"

section .text

global udelay
global ndelay
global mdelay

align 32
udelay:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push rdx

    mov r12, rdi            ; microseconds
    call tsc_read
    mov rbx, rax            ; start_tsc

    ; Target cycles = us * tsc_freq_hz / 1,000,000, using the frequency
    ; tsc_calibrate_pit measured at boot — not a hardcoded 3.0 GHz. A fixed
    ; assumption here is silently wrong on any host that isn't actually
    ; 3.0 GHz: too fast on a slower part turns every udelay/mdelay call into
    ; a much longer real-world wait than its caller asked for (a periodic
    ; fiber's `mdelay(1000)` between yields, for instance, taking tens of
    ; seconds of wall-clock time instead of one), and too slow on a faster
    ; part undershoots the same way. tsc_elapsed_nanos already reads this
    ; same global for the same reason; this just applies it symmetrically to
    ; the wait side.
    mov rax, r12
    mov rcx, [rel tsc_freq_hz]
    test rcx, rcx
    jnz .have_freq_us
    mov rcx, 3000000000     ; fallback, matches tsc_elapsed_nanos' default
.have_freq_us:
    mul rcx                 ; RDX:RAX = us * tsc_freq_hz
    mov rcx, 1000000
    div rcx                 ; RAX = needed cycles
    add rbx, rax            ; target_tsc = start_tsc + needed_cycles

.spin_us:
    pause
    call tsc_read
    cmp rax, rbx
    jb .spin_us

    pop rdx
    pop r12
    pop rbx
    pop rbp
    ret

align 32
ndelay:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push rdx

    mov r12, rdi            ; nanoseconds
    call tsc_read
    mov rbx, rax            ; start_tsc

    ; Target cycles = ns * tsc_freq_hz / 1,000,000,000 — see udelay above for
    ; why this reads the calibrated frequency instead of assuming 3.0 GHz.
    mov rax, r12
    mov rcx, [rel tsc_freq_hz]
    test rcx, rcx
    jnz .have_freq_ns
    mov rcx, 3000000000
.have_freq_ns:
    mul rcx                 ; RDX:RAX = ns * tsc_freq_hz
    mov rcx, 1000000000
    div rcx                 ; RAX = needed cycles
    add rbx, rax

.spin_ns:
    pause
    call tsc_read
    cmp rax, rbx
    jb .spin_ns

    pop rdx
    pop r12
    pop rbx
    pop rbp
    ret

align 32
mdelay:
    push rbp
    mov rbp, rsp
    ; rdi = milliseconds
    imul rdi, 1000
    call udelay
    pop rbp
    ret

%endif ; GUARD_LIB_TIME_DELAY_ASM
