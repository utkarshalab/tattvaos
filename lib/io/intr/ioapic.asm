; =============================================================================
; lib/io/intr/ioapic.asm
; IO-APIC redirection table routing driver.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_INTR_IOAPIC_ASM
%define IO_INTR_IOAPIC_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"
%include "lib/io/io.inc"

section .data
global io_ioapic_base
io_ioapic_base: dq 0xFEC00000       ; IO-APIC MMIO virtual base, populated by ACPI scan

section .text

; =============================================================================
; ioapic_read — Read a 32-bit register from the IO-APIC
; In : RDI = Register index
; Out: EAX = Register value
; RSO: RDI owned-in; RAX owned-out
; =============================================================================
IO_FUNC ioapic_read
    push    rcx

    mov     rcx, [rel io_ioapic_base]
    test    rcx, rcx
    jz      .err

    ; Write register index to IOREGSEL
    mov     [rcx + IOAPIC_REGSEL], edi
    ; Read register data from IOWIN
    mov     eax, [rcx + IOAPIC_IOWIN]
    jmp     .done

.err:
    xor     eax, eax

.done:
    pop     rcx
IO_ENDFUNC ioapic_read

; =============================================================================
; ioapic_write — Write a 32-bit register to the IO-APIC
; In : RDI = Register index
;      RSI = Value to write (32-bit)
; Out: None
; RSO: RDI, RSI owned-in
; =============================================================================
IO_FUNC ioapic_write
    push    rcx

    mov     rcx, [rel io_ioapic_base]
    test    rcx, rcx
    jz      .done

    ; Write register index to IOREGSEL
    mov     [rcx + IOAPIC_REGSEL], edi
    ; Write register data to IOWIN
    mov     [rcx + IOAPIC_IOWIN], esi

.done:
    pop     rcx
IO_ENDFUNC ioapic_write

; =============================================================================
; ioapic_route_irq — Route a hardware IRQ pin to a CPU core and vector
; In : RDI = IRQ Pin (0-23)
;      RSI = Vector number (0x20-0xFE)
;      RDX = APIC ID of destination core
; Out: None
; RSO: RDI, RSI, RDX owned-in
; =============================================================================
IO_FUNC ioapic_route_irq
    push    rbx
    push    rcx
    push    r8
    push    r9
    push    rdi
    push    rsi

    mov     r8, rdi                 ; R8 = IRQ pin
    mov     r9, rsi                 ; R9 = Vector number

    ; 1. Calculate low register index: 0x10 + irq * 2
    mov     rax, r8
    shl     rax, 1                  ; IRQ * 2
    add     rax, IOAPIC_REDTBL_BASE ; RAX = Redirection low register index

    ; Low 32 bits of redirection table:
    ; vector (bits 0-7) | delivery mode (bits 8-10, 0=Fixed) | dest mode (bit 11, 0=Physical)
    ; polarity (bit 13, 0=Active High) | trigger mode (bit 15, 0=Edge) | mask (bit 16, 0=Unmasked)
    mov     rsi, r9
    and     rsi, 0xFF               ; Only low 8 bits vector
    mov     rdi, rax                ; Register index
    call    ioapic_write

    ; 2. Calculate high register index: 0x10 + irq * 2 + 1
    mov     rax, r8
    shl     rax, 1
    add     rax, (IOAPIC_REDTBL_BASE + 1) ; High register index

    ; High 32 bits: destination APIC ID in bits 24-31
    mov     rsi, rdx
    and     rsi, 0xFF
    shl     rsi, 24                 ; RSI = APIC ID << 24
    mov     rdi, rax                ; Register index
    call    ioapic_write

    pop     rsi
    pop     rdi
    pop     r9
    pop     r8
    pop     rcx
    pop     rbx
IO_ENDFUNC ioapic_route_irq

%endif ; IO_INTR_IOAPIC_ASM
