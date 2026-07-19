; =============================================================================
; lib/io/const/uart.asm
; 16550 UART serial register offset constants.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_CONST_UART_ASM
%define IO_CONST_UART_ASM

; 16550 UART IO Port Registers Offsets (relative to COM base port)
UART_REG_THR        equ 0           ; Transmit Holding Register (Write-only, DLAB=0)
UART_REG_RBR        equ 0           ; Receiver Buffer Register (Read-only, DLAB=0)
UART_REG_DLL        equ 0           ; Divisor Latch Low (Read/Write, DLAB=1)
UART_REG_IER        equ 1           ; Interrupt Enable Register (Read/Write, DLAB=0)
UART_REG_DLH        equ 1           ; Divisor Latch High (Read/Write, DLAB=1)
UART_REG_IIR        equ 2           ; Interrupt Identification Register (Read-only)
UART_REG_FCR        equ 2           ; FIFO Control Register (Write-only)
UART_REG_LCR        equ 3           ; Line Control Register (Read/Write)
UART_REG_MCR        equ 4           ; Modem Control Register (Read/Write)
UART_REG_LSR        equ 5           ; Line Status Register (Read-only)
UART_REG_MSR        equ 6           ; Modem Status Register (Read-only)
UART_REG_SCR        equ 7           ; Scratch Register (Read/Write)

; UART Line Status Register (LSR) Flags
UART_LSR_DR         equ 0x01        ; Bit 0: Data Ready
UART_LSR_OE         equ 0x02        ; Bit 1: Overrun Error
UART_LSR_PE         equ 0x04        ; Bit 2: Parity Error
UART_LSR_FE         equ 0x08        ; Bit 3: Framing Error
UART_LSR_BI         equ 0x10        ; Bit 4: Break Interrupt
UART_LSR_THRE       equ 0x20        ; Bit 5: Transmitter Holding Register Empty
UART_LSR_TEMT       equ 0x40        ; Bit 6: Transmitter Empty
UART_LSR_FIFO_ERR   equ 0x80        ; Bit 7: Error in Receiver FIFO

; UART Line Control Register (LCR) Flags
UART_LCR_WLS_8      equ 0x03        ; 8-bit Word Length Select
UART_LCR_STB_1      equ 0x00        ; 1 Stop Bit
UART_LCR_PEN_NONE   equ 0x00        ; No Parity
UART_LCR_DLAB       equ 0x80        ; Divisor Latch Access Bit (DLAB)

; Default Serial Base Addresses
UART_COM1_BASE      equ 0x3F8
UART_COM2_BASE      equ 0x2F8

%endif ; IO_CONST_UART_ASM
