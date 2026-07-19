; =============================================================================
; lib/time/mono.asm
; Monotonic clock source interface.
;
; Implements nanosecond and millisecond resolution monotonic tickers based
; on scaled CPU Timestamp counter counts.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_TIME_MONO_ASM
%define IO_TIME_MONO_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"
%include "lib/time/time.inc"

section .text

global time_monotonic
global time_monotonic_ms

extern tsc_ns

; =============================================================================
; time_monotonic — Monotonically increasing nanoseconds since boot
; Out: RAX = Nanoseconds
; =============================================================================
IO_FUNC time_monotonic
    call    tsc_ns                  ; Returns nanoseconds since boot in RAX
    ret
IO_ENDFUNC time_monotonic

; =============================================================================
; time_monotonic_ms — Monotonically increasing milliseconds since boot
; Out: RAX = Milliseconds
; =============================================================================
IO_FUNC time_monotonic_ms
    push    rdx
    push    rcx

    call    tsc_ns                  ; RAX = nanoseconds since boot

    ; Convert nanoseconds to milliseconds: ms = ns / 1,000,000
    mov     rcx, 1000000            ; Divisor
    xor     rdx, rdx
    div     rcx                     ; RAX = ms, RDX = remainder

    pop     rcx
    pop     rdx
    ret
IO_ENDFUNC time_monotonic_ms

%endif ; IO_TIME_MONO_ASM
