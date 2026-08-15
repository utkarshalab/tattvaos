; =============================================================================
; Tattva OS — lib/ulog/format/timestamp_fmt.asm
; =============================================================================
; Renders a log_record_t.ts_ns (nanoseconds, from lib/time's monotonic clock)
; as seconds.nanoseconds directly to serial. Deliberately not zero-padded —
; a real calendar rendering belongs to lib/cal, out of scope for a logger
; that only needs "when relative to boot," not "what date."
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_FORMAT_TIMESTAMP_FMT_ASM
%define LIB_ULOG_FORMAT_TIMESTAMP_FMT_ASM

[BITS 64]

section .text

; -----------------------------------------------------------------------------
; timestamp_fmt_write — Input: RDI = ts_ns. Output: none, writes via uart.
; -----------------------------------------------------------------------------
global timestamp_fmt_write
timestamp_fmt_write:
    push rax
    push rbx
    push rdx

    mov rax, rdi
    mov rbx, 1000000000
    xor rdx, rdx
    div rbx                          ; RAX = seconds, RDX = nanos remainder

    push rdx                         ; nanos must survive the seconds print
    call uart_print_dec              ; uart_print_dec preserves all registers

    mov al, '.'
    call uart_putc

    pop rax
    call uart_print_dec

    pop rdx
    pop rbx
    pop rax
    ret

%endif ; LIB_ULOG_FORMAT_TIMESTAMP_FMT_ASM
