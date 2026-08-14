; =============================================================================
; lib/io/async/timeout.asm
; Timer tick handler and request timeout management.
;
; Binds vector 0x30 (LAPIC timer tick) to update global system ticks.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_ASYNC_TIMEOUT_ASM
%define IO_ASYNC_TIMEOUT_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/intr/isr.asm"

section .data
global global_io_ticks
global_io_ticks: dq 0

section .text

; =============================================================================
; io_timeout_handler — Vector 0x30 interrupt handler (LAPIC Timer Tick)
; Increments global system tick count and acknowledges LAPIC.
; =============================================================================
global io_timeout_handler
io_timeout_handler:
    ISR_ENTRY

    ; Increment global monotonic tick count
    inc     qword [rel global_io_ticks]

    ; Future: walk the active request list / timeout wheel and expire requests
    ; exceeding deadline (marking them IO_REQ_TIMEOUT / IO_ERR_TIMEOUT).

    call    lapic_send_eoi          ; Acknowledge vector in LAPIC
    ISR_EXIT

%endif ; IO_ASYNC_TIMEOUT_ASM
