; =============================================================================
; lib/time/tsc.asm
; Raw RDTSC clock reading and PIT-based frequency calibration.
;
; Calibrates raw CPU clock ticks using the legacy PIT Channel 2 gated over a
; 10ms window, and maps TSC tick scales to monotonic nanoseconds elapsed.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_TIME_TSC_ASM
%define IO_TIME_TSC_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"
%include "lib/time/time.inc"
%include "lib/io/error/codes.asm"

section .data
global global_tsc_hz
global_tsc_hz:      dq 2000000000   ; Calibrated frequency, default 2 GHz fallback

section .text

global tsc_read
global tsc_calibrate
global tsc_ns

; =============================================================================
; tsc_read — Read raw 64-bit Timestamp Counter (RDTSC)
; Out: RAX = 64-bit TSC ticks
; =============================================================================
IO_FUNC tsc_read
    rdtsc                           ; Read TSC into EDX:EAX
    shl     rdx, 32
    or      rax, rdx                ; Combine into RAX
    ret
IO_ENDFUNC tsc_read

; =============================================================================
; tsc_calibrate — Calibrate TSC frequency using legacy PIT Channel 2
; Out: RAX = Calibrated TSC frequency in Hz
; =============================================================================
IO_FUNC tsc_calibrate
    push    rbx
    push    rcx
    push    rdx
    push    r12
    push    r13

    ; 1. Configure PIT Channel 2: Mode 0 (one-shot), write LOBYTE/HIBYTE
    mov     al, 0xB0
    out     0x43, al                ; Port 0x43: Mode/Command Register

    ; 2. Load count 11932 (~10 milliseconds at 1.193182 MHz)
    ;    LOBYTE = 0x9C, HIBYTE = 0x2E
    mov     al, 0x9C
    out     0x42, al                ; Port 0x42: Channel 2 Data
    mov     al, 0x2E
    out     0x42, al

    ; 3. Enable PIT Channel 2 gate and disable speaker output
    in      al, 0x61
    and     al, 0xFD                ; Clear bit 1 (Disable speaker)
    or      al, 0x01                ; Set bit 0 (Enable Gate)
    out     0x61, al

    ; Read starting TSC value
    rdtsc
    shl     rdx, 32
    or      rax, rdx
    mov     r12, rax                ; R12 = start TSC

    ; 4. Spin-wait until PIT output (bit 5 of port 0x61) transitions high
.wait_pit:
    in      al, 0x61
    test    al, 0x20                ; Test bit 5
    jz      .wait_pit

    ; Read ending TSC value
    rdtsc
    shl     rdx, 32
    or      rax, rdx
    mov     r13, rax                ; R13 = end TSC

    ; 5. Disable PIT Channel 2 gate
    in      al, 0x61
    and     al, 0xFE                ; Clear bit 0
    out     0x61, al

    ; Calculate ticks elapsed: end - start
    sub     r13, r12                ; R13 = ticks in 10ms

    ; Prevent zero-ticks or negative-ticks in emulated hypervisors
    cmp     r13, 1000
    jae     .calc_hz
    mov     r13, 20000000           ; Assume 20 million ticks per 10ms (2 GHz)

.calc_hz:
    ; TSC Hz = ticks_in_10ms * 100
    mov     rax, r13
    mov     rcx, 100
    mul     rcx                     ; RAX = R13 * 100

    mov     [rel global_tsc_hz], rax ; Save calibrated frequency
    
    pop     r13
    pop     r12
    pop     rdx
    pop     rcx
    pop     rbx
    ret
IO_ENDFUNC tsc_calibrate

; =============================================================================
; tsc_ns — Return monotonic nanoseconds elapsed since processor boot
; Out: RAX = nanoseconds
; =============================================================================
IO_FUNC tsc_ns
    push    rdx
    push    rcx

    rdtsc                           ; EDX:EAX = current TSC
    shl     rdx, 32
    or      rax, rdx                ; RAX = TSC

    ; Scaled calculation: nanoseconds = (TSC * 1,000,000,000) / tsc_hz
    mov     rcx, 1000000000
    mul     rcx                     ; RDX:RAX = TSC * 1,000,000,000
    
    mov     rcx, [rel global_tsc_hz]
    test    rcx, rcx
    jnz     .divide
    mov     rcx, 2000000000         ; Fallback divisor if 0
.divide:
    div     rcx                     ; RAX = nanoseconds since boot

    pop     rcx
    pop     rdx
    ret
IO_ENDFUNC tsc_ns

%endif ; IO_TIME_TSC_ASM
