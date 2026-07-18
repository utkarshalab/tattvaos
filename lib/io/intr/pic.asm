; =============================================================================
; lib/io/intr/pic.asm
; 8259 legacy Programmable Interrupt Controller (PIC) management.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_INTR_PIC_ASM
%define IO_INTR_PIC_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"

; 8259 PIC Ports
PIC1_CMD            equ 0x20
PIC1_DATA           equ 0x21
PIC2_CMD            equ 0xA0
PIC2_DATA           equ 0xA1

section .text

;extern port_out8

; =============================================================================
; pic_remap — Remap the legacy 8259 PIC vectors to 0x20-0x2F
; In : None
; Out: None
; =============================================================================
IO_FUNC pic_remap
    ; 1. ICW1: Initialize master and slave PIC
    mov     rdi, PIC1_CMD
    mov     rsi, 0x11               ; ICW1_INIT | ICW1_ICW4
    call    port_out8

    mov     rdi, PIC2_CMD
    mov     rsi, 0x11
    call    port_out8

    ; 2. ICW2: Vector offset mapping (Master=0x20, Slave=0x28)
    mov     rdi, PIC1_DATA
    mov     rsi, 0x20               ; Master offset = 0x20 (exceptions end at 0x1F)
    call    port_out8

    mov     rdi, PIC2_DATA
    mov     rsi, 0x28               ; Slave offset = 0x28
    call    port_out8

    ; 3. Cascade setup
    mov     rdi, PIC1_DATA
    mov     rsi, 0x04               ; Master has slave on IRQ2 (0b00000100)
    call    port_out8

    mov     rdi, PIC2_DATA
    mov     rsi, 0x02               ; Slave identity cascade 2
    call    port_out8

    ; 4. ICW4: Additional environment parameters
    mov     rdi, PIC1_DATA
    mov     rsi, 0x01               ; 8086/88 (MCS-80/85) mode
    call    port_out8

    mov     rdi, PIC2_DATA
    mov     rsi, 0x01
    call    port_out8

    ; 5. Mask all interrupts to disable legacy PIC (we use APIC instead)
    mov     rdi, PIC1_DATA
    mov     rsi, 0xFF               ; Mask all master interrupts
    call    port_out8

    mov     rdi, PIC2_DATA
    mov     rsi, 0xFF               ; Mask all slave interrupts
    call    port_out8
IO_ENDFUNC pic_remap

%endif ; IO_INTR_PIC_ASM
