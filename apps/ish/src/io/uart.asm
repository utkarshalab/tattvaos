; =============================================================================
; File     : apps/ish/src/io/uart.asm
; Project  : Utkarsha OS — Ishana Shell
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: UART/serial frontend for headless console (COM1, 0x3F8).
; =============================================================================

%ifndef ISH_UART_ASM
%define ISH_UART_ASM

%include "inc/frontend.inc"
%include "lib/io/io.asm"

bits 64

; UART registers (COM1 base 0x3F8)
UART_DATA     equ 0x3F8
UART_IER      equ 0x3F9
UART_IIR      equ 0x3FA
UART_LCR      equ 0x3FB
UART_MCR      equ 0x3FC
UART_LSR      equ 0x3FD
UART_MSR      equ 0x3FE

LSR_DR        equ (1 << 0)    ; Data Ready
LSR_THRE      equ (1 << 5)    ; Transmitter Holding Register Empty

section .data
align 16
uart_frontend_name:   db "uart0", 0

section .bss
align 16
uart_buf_pos:         resq 1

section .text

; -----------------------------------------------------------------------------
; uart_init — Initialize UART (115200 baud, 8N1)
; -----------------------------------------------------------------------------
global uart_init
uart_init:
    PROLOGUE_SAVE rbx

    ; Set DLAB to access baud rate divisor registers
    mov     dx, UART_LCR
    mov     al, 0x80
    out     dx, al

    ; Set baud rate divisor = 1 (115200 baud with 1.8432 MHz clock)
    mov     dx, UART_DATA
    mov     al, 0x01
    out     dx, al
    mov     dx, UART_IER
    mov     al, 0x00
    out     dx, al

    ; Set 8N1, clear DLAB
    mov     dx, UART_LCR
    mov     al, 0x03
    out     dx, al

    ; Enable FIFO, clear RTS
    mov     dx, UART_MCR
    mov     al, 0x08
    out     dx, al

    mov     qword [uart_buf_pos], 0
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; uart_shutdown — Shutdown UART
; -----------------------------------------------------------------------------
global uart_shutdown
uart_shutdown:
    ret

; -----------------------------------------------------------------------------
; uart_read_line — Read a line from UART with echo and backspace
; Input:  rdi = buffer, rsi = max_len
; Output: rax = bytes read or -1 on EOF
; -----------------------------------------------------------------------------
global uart_read_line
uart_read_line:
    PROLOGUE_SAVE rbx, r12, r13

    mov     r12, rdi                      ; r12 = buffer
    mov     r13, rsi                      ; r13 = max_len
    mov     qword [uart_buf_pos], 0

.read_char:
    cmp     qword [uart_buf_pos], r13
    jge     .buffer_full

    call    uart_getc_poll                ; rax = char or -1 (non-blocking)
    cmp     rax, -1
    je      .read_char                    ; no char yet, poll again

    cmp     rax, 0x0A                     ; newline (LF)
    je      .newline
    cmp     rax, 0x0D                     ; carriage return (CR)
    je      .newline

    cmp     rax, 0x08                     ; backspace
    je      .backspace
    cmp     rax, 0x7F                     ; delete
    je      .backspace

    cmp     rax, 0x03                     ; Ctrl-C
    je      .ctrl_c

    ; Echo char
    mov     rdi, rax
    call    uart_putc

    ; Store char
    mov     rbx, [uart_buf_pos]
    mov     [r12 + rbx], al
    inc     qword [uart_buf_pos]
    jmp .read_char

.newline:
    call    uart_putc                     ; echo newline
    mov     rbx, [uart_buf_pos]
    mov     byte [r12 + rbx], 0           ; null terminate
    mov     rax, [uart_buf_pos]
    jmp .done

.backspace:
    cmp     qword [uart_buf_pos], 0
    je      .read_char
    dec     qword [uart_buf_pos]
    mov     rdi, 0x08
    call    uart_putc
    mov     rdi, ' '
    call    uart_putc
    mov     rdi, 0x08
    call    uart_putc
    jmp .read_char

.ctrl_c:
    mov     dword [ish_ctx_interrupt], 1
    mov     rdi, msg_ctrl_c
    call    frontend_write_str
    mov     rax, -1
    jmp .done

.buffer_full:
    mov     rax, -1
    jmp .done

.done:
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; -----------------------------------------------------------------------------
; uart_write — Write bytes to UART
; Input:  rdi = ptr, rsi = len
; -----------------------------------------------------------------------------
global uart_write
uart_write:
    PROLOGUE_SAVE rbx, rcx
    mov     rbx, rdi
    mov     rcx, rsi
.write_loop:
    test    rcx, rcx
    jz      .write_done
    mov     rdi, [rbx]
    call    uart_putc
    add     rbx, 1
    dec     rcx
    jmp .write_loop
.write_done:
    EPILOGUE_RESTORE rbx, rcx
    ret

; -----------------------------------------------------------------------------
; uart_write_str — Write null-terminated string to UART
; Input:  rdi = str
; -----------------------------------------------------------------------------
global uart_write_str
uart_write_str:
    PROLOGUE_SAVE rbx
    mov     rbx, rdi
.str_loop:
    mov     al, [rbx]
    test    al, al
    jz      .str_done
    call    uart_putc
    add     rbx, 1
    jmp .str_loop
.str_done:
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; uart_write_char — Write single char to UART
; Input:  al = char
; -----------------------------------------------------------------------------
global uart_write_char
uart_write_char:
    call    uart_putc
    ret

; -----------------------------------------------------------------------------
; uart_set_prompt — No-op for UART
; -----------------------------------------------------------------------------
global uart_set_prompt
uart_set_prompt:
    ret

; -----------------------------------------------------------------------------
; uart_clear_line — Clear current line (UART)
; -----------------------------------------------------------------------------
global uart_clear_line
uart_clear_line:
    PROLOGUE_SAVE rbx, rcx
    mov     rcx, 80
.clear_loop:
    mov     rdi, ' '
    call    uart_putc
    dec     rcx
    jnz     .clear_loop
    mov     rcx, 80
.clear_back:
    mov     rdi, 0x08
    call    uart_putc
    dec     rcx
    jnz     .clear_back
    EPILOGUE_RESTORE rbx, rcx
    ret

; -----------------------------------------------------------------------------
; uart_get_char — Get single char (non-blocking)
; Input:  none
; Output: rax = char or -1
; -----------------------------------------------------------------------------
global uart_get_char
uart_get_char:
    call    uart_getc_poll
    ret

; -----------------------------------------------------------------------------
; uart_is_tty — UART is always a TTY
; Output: rax = 1
; -----------------------------------------------------------------------------
global uart_is_tty
uart_is_tty:
    mov     eax, 1
    ret

; -----------------------------------------------------------------------------
; uart_get_size — Terminal size (default 80x24)
; Input:  rsi = ptr to cols, rdx = ptr to rows
; -----------------------------------------------------------------------------
global uart_get_size
uart_get_size:
    PROLOGUE_SAVE rbx
    mov     rbx, rsi
    mov     dword [rbx], 80               ; cols
    mov     dword [rbx + 4], 24           ; rows
    EPILOGUE_RESTORE rbx
    ret

section .rodata
align 16
msg_ctrl_c:   db "^C", 0x0A, 0

; UART frontend vtable
align 16
uart_frontend_vtable:
    .name:          dq uart_frontend_name
    .init:          dq uart_init
    .shutdown:      dq uart_shutdown
    .read_line:     dq uart_read_line
    .write:         dq uart_write
    .write_str:     dq uart_write_str
    .write_char:    dq uart_write_char
    .set_prompt:    dq uart_set_prompt
    .clear_line:    dq uart_clear_line
    .move_cursor:   dq 0
    .get_char:      dq uart_get_char
    .is_tty:        dq uart_is_tty
    .get_size:      dq uart_get_size
    .private:       dq 0

%endif ; ISH_UART_ASM