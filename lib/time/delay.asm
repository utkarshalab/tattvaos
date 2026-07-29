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
    
    mov r12, rdi            ; microseconds
    call tsc_read
    mov rbx, rax            ; start_tsc
    
    ; Target cycles = us * (tsc_freq_hz / 1,000,000)
    mov rax, r12
    mov rcx, 3000           ; 3.0 GHz = 3000 cycles / microsecond
    mul rcx
    add rbx, rax            ; target_tsc = start_tsc + needed_cycles

.spin_us:
    pause
    call tsc_read
    cmp rax, rbx
    jb .spin_us

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
    
    mov r12, rdi            ; nanoseconds
    call tsc_read
    mov rbx, rax            ; start_tsc
    
    mov rax, r12
    mov rcx, 3              ; 3 cycles / nanosecond
    mul rcx
    add rbx, rax

.spin_ns:
    pause
    call tsc_read
    cmp rax, rbx
    jb .spin_ns

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
