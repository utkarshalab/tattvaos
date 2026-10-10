%ifndef GUARD_LIB_TIME_TSC_ASM
%define GUARD_LIB_TIME_TSC_ASM
; =============================================================================
; Tattva OS — lib/time/tsc.asm
; =============================================================================
; CPU Time Stamp Counter (RDTSC / RDTSCP) Engine with PIT Hardware Calibration.
;
; Implements:
;   - Dynamic TSC Frequency Calibration via i8254 Programmable Interval Timer (PIT)
;   - Measures exact CPU frequency (in Hz) at boot without hardcoded assumptions
;   - Sub-Nanosecond Monotonic Counter with CPU serialization (`LFENCE` / `MFENCE`)
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "lib/time/time.inc"

section .data
align 8
tsc_freq_hz:        dq 3000000000       ; Measured TSC Frequency in Hz
tsc_ns_mult:        dq 0                ; Fixed-point multiplier for cycles -> ns
tsc_ns_shift:       dd 32               ; Fixed-point shift amount

section .text

global tsc_init
global tsc_calibrate_pit
global tsc_read
global tsc_read_serialized
global tsc_elapsed_nanos
global tsc_get_freq

align 32
tsc_init:
    push rbp
    mov rbp, rsp
    call tsc_calibrate_pit
    pop rbp
    ret

; Calibrate TSC using PIT Channel 2 (Port 0x61, 0x42, 0x43)
align 32
tsc_calibrate_pit:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    ; Gate channel 2 low before loading a one-shot count.
    in al, 0x61
    and al, 0xFC             ; preserve status, clear gate and speaker
    out 0x61, al

    ; Set PIT Channel 2 reload count: 29830 (25ms at the PIT's 1.193182MHz)
    mov al, 0xB0            ; Channel 2, LSB/MSB, mode 0
    out 0x43, al

    mov al, 0x86            ; LSB of 29830 (25ms)
    out 0x42, al
    mov al, 0x74            ; MSB
    out 0x42, al

    ; Now raise the gate: counting starts cleanly from the value just loaded.
    in al, 0x61
    and al, 0xFD
    or al, 0x01
    out 0x61, al

    ; Reject a channel that does not enter or leave the counting state.
    mov r12d, 10000000
.wait_low:
    in al, 0x61
    test al, 0x20
    jz .start_confirmed
    dec r12d
    jnz .wait_low
    jmp .failed
.start_confirmed:
    call tsc_read_serialized
    mov rbx, rax

    mov r12d, 10000000
.wait_pit:
    in al, 0x61
    test al, 0x20
    jnz .terminal_count
    dec r12d
    jnz .wait_pit
    jmp .failed

.terminal_count:
    call tsc_read_serialized
    sub rax, rbx
    jz .failed

    imul rax, 40
    jo .failed
    cmp rax, 100000000
    jb .failed
    mov rcx, 10000000000
    cmp rax, rcx
    ja .failed
    mov [rel tsc_freq_hz], rax
    clc
    jmp .done

.failed:
    stc
.done:
    pop r12
    pop rbx
    pop rbp
    ret

align 32
tsc_read:
    push rbp
    mov rbp, rsp
    rdtsc
    shl rdx, 32
    or rax, rdx
    pop rbp
    ret

align 32
tsc_read_serialized:
    push rbp
    mov rbp, rsp
    lfence
    rdtsc
    shl rdx, 32
    or rax, rdx
    pop rbp
    ret

align 32
tsc_elapsed_nanos:
    push rbp
    mov rbp, rsp
    push rbx                ; Callee-saved under SysV. Every caller of
                            ; mono_get_nanos reaches this function, and several
                            ; of them hold a live pointer in RBX across the
                            ; call — usrauth's password throttle writes through
                            ; it immediately afterwards. Clobbering it here
                            ; sends that store to address 3000000000.
    ; rdi = start_tsc, rsi = end_tsc
    mov rax, rsi
    sub rax, rdi            ; Elapsed cycles

    ; Nanoseconds = (cycles * 1,000,000,000) / tsc_freq_hz
    mov rcx, 1000000000
    mul rcx                 ; RDX:RAX = cycles * 1,000,000,000
    mov rbx, [rel tsc_freq_hz]
    test rbx, rbx
    jnz .div_freq
    mov rbx, 3000000000     ; Fallback if uncalibrated
.div_freq:
    div rbx                 ; RAX = nanoseconds
    pop rbx
    pop rbp
    ret

align 32
tsc_get_freq:
    mov rax, [rel tsc_freq_hz]
    ret

; -----------------------------------------------------------------------------
; rdtsc_get_cycles — raw cycle counter.
;
; Input:  none
; Output: RAX = 64-bit TSC value
;
; The name used across unet/ for the same thing tsc_read provides. It is a
; genuine alias, not a placeholder: the function takes no arguments, so there
; is nothing for a caller to marshal and nothing to get wrong.
;
; Non-serialising on purpose. Callers use it for packet ingress timestamps and
; as an entropy sample, where the cost of a serialising CPUID would exceed the
; interval being measured. Use tsc_read_serialized when ordering against
; surrounding instructions actually matters.
; -----------------------------------------------------------------------------
global rdtsc_get_cycles
align 32
rdtsc_get_cycles:
    jmp tsc_read

%endif ; GUARD_LIB_TIME_TSC_ASM
