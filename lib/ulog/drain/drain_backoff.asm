; =============================================================================
; Tattva OS — lib/ulog/drain/drain_backoff.asm
; =============================================================================
; Exponential backoff between idle drain_fiber.asm passes — an idle logger
; should cost close to nothing, not spin re-checking every ring on every
; scheduler turn. Resets to ULOG_BACKOFF_MIN_NANOS the moment there's real
; work again.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_DRAIN_DRAIN_BACKOFF_ASM
%define LIB_ULOG_DRAIN_DRAIN_BACKOFF_ASM

[BITS 64]

%include "lib/ulog/config/defaults.inc"

section .bss
alignb 8
global ulog_backoff_current_ns
ulog_backoff_current_ns: resq 1

section .text

; -----------------------------------------------------------------------------
; drain_backoff_reset
; -----------------------------------------------------------------------------
global drain_backoff_reset
drain_backoff_reset:
    mov qword [ulog_backoff_current_ns], ULOG_BACKOFF_MIN_NANOS
    ret

; -----------------------------------------------------------------------------
; drain_backoff_wait — sleeps the current backoff duration, then doubles it
; (capped at ULOG_BACKOFF_MAX_NANOS) for next time
; -----------------------------------------------------------------------------
global drain_backoff_wait
drain_backoff_wait:
    push rax

    mov rdi, [ulog_backoff_current_ns]
    call ndelay                      ; lib/time/delay.asm's nanosecond delay;
                                      ; this file called it delay_ns, which
                                      ; doesn't exist anywhere in the tree

    mov rax, [ulog_backoff_current_ns]
    shl rax, 1
    cmp rax, ULOG_BACKOFF_MAX_NANOS
    jle .store
    mov rax, ULOG_BACKOFF_MAX_NANOS
.store:
    mov [ulog_backoff_current_ns], rax

    pop rax
    ret

%endif ; LIB_ULOG_DRAIN_DRAIN_BACKOFF_ASM
