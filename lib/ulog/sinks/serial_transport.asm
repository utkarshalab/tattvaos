; =============================================================================
; Tattva OS — lib/ulog/sinks/serial_transport.asm
; =============================================================================
; The always-on sink — registered by init/full_init.asm before anything else,
; since it's the one output that works from the earliest boot instruction
; onward. Implements the sink_iface.inc contract over kernel/drivers/serial/
; uart.asm, which is already polling/synchronous, so write_fn can't fail in
; any way this sink detects — it always reports the full count written.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_SINKS_SERIAL_TRANSPORT_ASM
%define LIB_ULOG_SINKS_SERIAL_TRANSPORT_ASM

[BITS 64]

%include "lib/ulog/ulog.inc"

section .text

; -----------------------------------------------------------------------------
; serial_sink_write — sink_t.write_fn
; Input:  RDI = log_record_t* batch, RSI = count
; Output: RAX = count (always — see header note)
; -----------------------------------------------------------------------------
global serial_sink_write
serial_sink_write:
    push rbx
    push r12
    push r13

    mov rbx, rdi
    mov r12, rsi
    xor r13, r13

.loop:
    cmp r13, r12
    jae .done

    mov rax, r13
    imul rax, rax, LOG_RECORD_SIZE
    add rax, rbx
    mov rdi, rax
    call serial_format_record

    inc r13
    jmp .loop

.done:
    mov rax, r12
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; serial_sink_flush — sink_t.flush_fn. UART writes are already synchronous.
; -----------------------------------------------------------------------------
global serial_sink_flush
serial_sink_flush:
    mov rax, 1
    ret

%endif ; LIB_ULOG_SINKS_SERIAL_TRANSPORT_ASM
