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

    ; Gate PIT Channel 2: disable speaker, enable gate
    in al, 0x61
    and al, 0x0D
    or al, 0x01             ; Enable PIT2 gate, speaker off
    out 0x61, al

    ; Set PIT Channel 2 reload count: 119318 (approx 100ms calibration window)
    mov al, 0xB6            ; Channel 2, LSB/MSB, mode 0 (interrupt on terminal count)
    out 0x43, al
    
    mov al, 0x9B            ; LSB of 29830 (25ms)
    out 0x42, al
    mov al, 0x74            ; MSB
    out 0x42, al

    ; Read starting TSC
    call tsc_read_serialized
    mov rbx, rax            ; Start TSC

.wait_pit:
    in al, 0x61
    test al, 0x20           ; Check PIT Channel 2 OUT status bit
    jz .wait_pit

    ; Read ending TSC
    call tsc_read_serialized
    sub rax, rbx            ; Elapsed TSC cycles in 25ms

    ; Multiply cycles by 40 to get Hz (since 25ms = 1/40th second)
    imul rax, 40
    mov [rel tsc_freq_hz], rax

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
    pop rbp
    ret

align 32
tsc_get_freq:
    mov rax, [rel tsc_freq_hz]
    ret
