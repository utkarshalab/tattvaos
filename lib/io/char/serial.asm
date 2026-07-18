; =============================================================================
; lib/io/char/serial.asm
; 16550 UART serial driver implementation.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_CHAR_SERIAL_ASM
%define IO_CHAR_SERIAL_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"
%include "lib/io/error/codes.asm"

section .text

; These will be resolved during compilation/linking (either same unit or extern)
;extern port_in8
;extern port_out8

; =============================================================================
; serial_init — Initialize 16550 COM port to 115200 8N1 with loopback test.
; In : RDI = UART base address (e.g. 0x3F8)
; Out: RAX = 0 on success, or negative error code (IO_ERR_NO_DEVICE) on failure
; RSO: RBX = base (callee-saved); RAX owned-out
; =============================================================================
IO_FUNC serial_init
    guard_null rdi
    push    rbx
    mov     rbx, rdi                ; RBX = UART base

    ; 1. Disable all interrupts
    lea     rdi, [rbx + 1]          ; IER (Interrupt Enable Register)
    xor     rsi, rsi
    call    port_out8

    ; 2. Enable Loopback Mode for presence test
    lea     rdi, [rbx + 4]          ; MCR (Modem Control Register)
    mov     rsi, 0x1E               ; Set loopback bit (0x10) + RTS/DTR/OUT1/OUT2
    call    port_out8

    ; 3. Write test pattern and verify match
    mov     rdi, rbx                ; THR (Transmit Holding Register)
    mov     rsi, 0xAE               ; Test pattern byte
    call    port_out8

    ; Wait briefly for loopback propagation
    mov     rdx, 1000
.settle:
    dec     rdx
    jnz     .settle

    ; Check if DR (Data Ready) bit is set in LSR
    lea     rdi, [rbx + 5]          ; LSR (Line Status Register)
    call    port_in8
    test    al, 0x01                ; DR is bit 0
    jz      .absent

    ; Read byte from Receiver Buffer Register (RBR)
    mov     rdi, rbx
    call    port_in8
    cmp     al, 0xAE
    jne     .absent

    ; 4. Restore normal mode and configure divisor latch
    lea     rdi, [rbx + 3]          ; LCR (Line Control Register)
    mov     rsi, 0x80               ; Enable DLAB (Divisor Latch Access Bit)
    call    port_out8

    mov     rdi, rbx                ; DLL (Divisor Latch Low)
    mov     rsi, 1                  ; divisor = 1 for 115200 baud
    call    port_out8

    lea     rdi, [rbx + 1]          ; DLM (Divisor Latch High)
    xor     rsi, rsi
    call    port_out8

    lea     rdi, [rbx + 3]          ; LCR
    mov     rsi, 0x03               ; 8N1, DLAB = 0
    call    port_out8

    ; 5. Enable FIFO, clear RX/TX, 14-byte trigger
    lea     rdi, [rbx + 2]          ; FCR (FIFO Control Register)
    mov     rsi, 0xC7
    call    port_out8

    ; 6. Configure Modem Control (RTS/DTR active, OUT2 enabled, normal mode)
    lea     rdi, [rbx + 4]          ; MCR
    mov     rsi, 0x0B
    call    port_out8

    xor     rax, rax                ; Return 0 (Success)
    jmp     .done

.absent:
    mov     rax, IO_ERR_NO_DEVICE   ; Return negative error code

.done:
    pop     rbx
IO_ENDFUNC serial_init

; =============================================================================
; serial_putc — Synchronous byte write to the UART
; In : RDI = UART base address
;      RSI = Byte character to transmit
; RSO: RBX = base, R12 = char (callee-saved)
; =============================================================================
IO_FUNC serial_putc
    push    rbx
    push    r12
    mov     rbx, rdi
    mov     r12, rsi

.wait_tx:
    lea     rdi, [rbx + 5]          ; LSR (Line Status Register)
    call    port_in8
    test    al, 0x20                ; THRE (Transmitter Holding Register Empty) is bit 5
    jz      .wait_tx                ; Spin until ready

    mov     rdi, rbx                ; THR
    mov     rsi, r12
    call    port_out8

    pop     r12
    pop     rbx
IO_ENDFUNC serial_putc

%endif ; IO_CHAR_SERIAL_ASM
