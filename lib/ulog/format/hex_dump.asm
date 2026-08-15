; =============================================================================
; Tattva OS — lib/ulog/format/hex_dump.asm
; =============================================================================
; Annotated raw-buffer dump for "log these N bytes" error paths — a corrupt
; crypto handshake record, a malformed uxfs journal block. 16 bytes per line,
; offset prefix, straight to serial (the buffer being dumped is usually
; exactly what's suspect, so this doesn't route through the ring — the same
; reasoning as panic/panic_emit.asm, applied to a narrower case).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_FORMAT_HEX_DUMP_ASM
%define LIB_ULOG_FORMAT_HEX_DUMP_ASM

[BITS 64]

section .text

; -----------------------------------------------------------------------------
; hex_dump_write — Input: RDI = buffer, RSI = length. Output: none.
; -----------------------------------------------------------------------------
global hex_dump_write
hex_dump_write:
    push rbx
    push r12
    push r13

    mov rbx, rdi                     ; buffer
    mov r12, rsi                      ; length
    xor r13, r13                       ; offset

.line_loop:
    cmp r13, r12
    jae .done

    mov eax, r13d
    call uart_print_hex32
    mov al, ':'
    call uart_putc
    mov al, ' '
    call uart_putc

    xor rcx, rcx
.byte_loop:
    cmp rcx, 16
    jae .line_end
    mov rax, r13
    add rax, rcx
    cmp rax, r12
    jae .pad

    movzx eax, byte [rbx + rax]
    call .print_hex_byte
    mov al, ' '
    call uart_putc
    inc rcx
    jmp .byte_loop

.pad:
    mov al, ' '
    call uart_putc
    mov al, ' '
    call uart_putc
    mov al, ' '
    call uart_putc
    inc rcx
    jmp .byte_loop

.line_end:
    mov al, 0x0D
    call uart_putc
    mov al, 0x0A
    call uart_putc
    add r13, 16
    jmp .line_loop

.done:
    pop r13
    pop r12
    pop rbx
    ret

; ---- .print_hex_byte: AL = byte -> two hex chars via uart_putc ------------
.print_hex_byte:
    push rax
    push rbx
    mov bl, al
    shr al, 4
    call .nibble
    mov al, bl
    and al, 0x0F
    call .nibble
    pop rbx
    pop rax
    ret

.nibble:
    cmp al, 10
    jl .digit
    add al, 'A' - 10
    jmp .emit
.digit:
    add al, '0'
.emit:
    call uart_putc
    ret

%endif ; LIB_ULOG_FORMAT_HEX_DUMP_ASM
