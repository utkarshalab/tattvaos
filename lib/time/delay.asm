; =============================================================================
; lib/time/delay.asm
; Yielding delay routines.
;
; Implements nanosecond and millisecond delays that query the monotonic clock
; and yield CPU execution slices to the scheduler loop between ticks.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_TIME_DELAY_ASM
%define IO_TIME_DELAY_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"
%include "lib/time/time.inc"

section .text

global time_delay_ns
global time_delay_ms

extern time_monotonic
extern sched_yield

; =============================================================================
; time_delay_ns — Block execution for a requested number of nanoseconds
; In : RDI = Nanoseconds to delay
; =============================================================================
IO_FUNC time_delay_ns
    push    rbx
    push    rcx
    push    rdx
    push    r12
    push    r13

    mov     r12, rdi                ; r12 = delay duration in ns

    call    time_monotonic
    mov     r13, rax                ; r13 = start timestamp (ns)

.loop:
    call    time_monotonic          ; RAX = current timestamp
    mov     rcx, rax
    sub     rcx, r13                ; RCX = elapsed ns
    cmp     rcx, r12                ; Compare elapsed vs duration
    jae     .done

    ; Yield CPU execution slot
    call    sched_yield
    jmp     .loop

.done:
    pop     r13
    pop     r12
    pop     rdx
    pop     rcx
    pop     rbx
    ret
IO_ENDFUNC time_delay_ns

; =============================================================================
; time_delay_ms — Block execution for a requested number of milliseconds
; In : RDI = Milliseconds to delay
; =============================================================================
IO_FUNC time_delay_ms
    push    rax
    push    rcx
    push    rdx
    push    rdi

    ; Convert milliseconds to nanoseconds: ns = ms * 1,000,000
    mov     rax, rdi
    mov     rcx, 1000000
    mul     rcx                     ; RDX:RAX = ms * 1,000,000

    mov     rdi, rax                ; RDI = ns duration
    call    time_delay_ns

    pop     rdi
    pop     rdx
    pop     rcx
    pop     rax
    ret
IO_ENDFUNC time_delay_ms

%endif ; IO_TIME_DELAY_ASM
