; =============================================================================
; Tattva OS — lib/ulog/sinks/serial_format.asm
; =============================================================================
; The seam between "how a record becomes a serial line" and "how bytes get
; onto COM1." Forwards to format/text_render.asm today; kept as its own file
; because a colorized or width-limited serial format is a reasonable future
; change that shouldn't need to touch serial_transport.asm at all.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_SINKS_SERIAL_FORMAT_ASM
%define LIB_ULOG_SINKS_SERIAL_FORMAT_ASM

[BITS 64]

section .text

; -----------------------------------------------------------------------------
; serial_format_record — Input: RDI = log_record_t*. Output: none.
; -----------------------------------------------------------------------------
global serial_format_record
serial_format_record:
    jmp text_render_line

%endif ; LIB_ULOG_SINKS_SERIAL_FORMAT_ASM
