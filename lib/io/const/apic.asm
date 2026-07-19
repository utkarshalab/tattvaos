; =============================================================================
; lib/io/const/apic.asm
; Local APIC and I/O APIC register offsets and vector mappings.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_CONST_APIC_ASM
%define IO_CONST_APIC_ASM

; Local APIC Register Offsets (relative to io_lapic_base)
APIC_REG_ID         equ 0x020       ; Local APIC ID
APIC_REG_VER        equ 0x030       ; APIC Version
APIC_REG_TPR        equ 0x080       ; Task Priority
APIC_REG_APR        equ 0x090       ; Arbitration Priority
APIC_REG_PPR        equ 0x0A0       ; Processor Priority
APIC_REG_EOI        equ 0x0B0       ; End of Interrupt (Write-only)
APIC_REG_LDR        equ 0x0D0       ; Logical Destination
APIC_REG_DFR        equ 0x0E0       ; Destination Format
APIC_REG_SVR        equ 0x0F0       ; Spurious Interrupt Vector
APIC_REG_ISR_BASE   equ 0x100       ; In-Service Register Base (8 registers)
APIC_REG_TMR_BASE   equ 0x180       ; Trigger Mode Register Base
APIC_REG_IRR_BASE   equ 0x200       ; Interrupt Request Register Base
APIC_REG_ESR        equ 0x280       ; Error Status
APIC_REG_ICR_LOW    equ 0x300       ; Interrupt Command Register [31:0]
APIC_REG_ICR_HIGH   equ 0x310       ; Interrupt Command Register [63:32]
APIC_REG_LVT_TMR    equ 0x320       ; LVT Timer
APIC_REG_LVT_LINT0  equ 0x350       ; LVT LINT0
APIC_REG_LVT_LINT1  equ 0x360       ; LVT LINT1
APIC_REG_LVT_ERR    equ 0x370       ; LVT Error
APIC_REG_TMR_INIT   equ 0x380       ; Timer Initial Count
APIC_REG_TMR_CURR   equ 0x390       ; Timer Current Count
APIC_REG_TMR_DIV    equ 0x3E0       ; Timer Divide Configuration

; I/O APIC Register Offsets
IOAPIC_REG_INDEX    equ 0x00        ; Direct I/O index register (u32)
IOAPIC_REG_DATA     equ 0x10        ; Direct I/O data register (u32)

; I/O APIC Indirect Register Offsets
IOAPIC_IND_ID       equ 0x00        ; I/O APIC ID
IOAPIC_IND_VER      equ 0x01        ; I/O APIC Version
IOAPIC_IND_ARB      equ 0x02        ; Arbitration ID
IOAPIC_IND_RED_BASE equ 0x10        ; Redirection Table Base (2 registers per IRQ pin)

; Dynamic Interrupt Allocation Vector Boundaries
APIC_VEC_EXC_LIMIT  equ 0x20        ; Exception vector upper boundary (32)
APIC_VEC_PCI_START  equ 0x40        ; Dynamic MSI-X vector start boundary (64)
APIC_VEC_PCI_LIMIT  equ 0xF0        ; Dynamic MSI-X vector upper boundary (240)
APIC_VEC_SPURIOUS   equ 0xFF        ; Spurious vector (255)

%endif ; IO_CONST_APIC_ASM
