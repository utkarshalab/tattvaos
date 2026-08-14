; =============================================================================
; lib/io/intr/ioapic_mask.asm
; IO-APIC redirection table interrupt pin masking controls.
;
; Implements dynamic disable (mask) and enable (unmask) capabilities for
; legacy hardware IRQ pins mapped via the I/O APIC redirect list.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_INTR_IOAPIC_MASK_ASM
%define IO_INTR_IOAPIC_MASK_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"
%include "lib/io/io.inc"

section .text

global ioapic_mask_irq
global ioapic_unmask_irq


; =============================================================================
; ioapic_mask_irq — Disable (mask) a specific hardware IRQ pin on IO-APIC
; In : RDI = Pin index (0-23)
; =============================================================================
IO_FUNC ioapic_mask_irq
    push    rbx
    push    rcx

    mov     rbx, rdi                ; RBX = Pin index

    ; Redirection register low dword offset = 0x10 + pin * 2
    shl     rdi, 1                  ; pin * 2
    add     rdi, 0x10               ; 0x10 + pin * 2
    mov     rcx, rdi                ; RCX = Register index

    call    ioapic_read             ; EAX = current low redirection dword

    or      eax, 0x10000            ; Set Bit 16 (Interrupt Mask Bit)

    mov     rdi, rcx                ; RDI = Register index
    mov     rsi, rax                ; RSI = updated value
    call    ioapic_write

    pop     rcx
    pop     rbx
    ret
IO_ENDFUNC ioapic_mask_irq

; =============================================================================
; ioapic_unmask_irq — Enable (unmask) a specific hardware IRQ pin on IO-APIC
; In : RDI = Pin index (0-23)
; =============================================================================
IO_FUNC ioapic_unmask_irq
    push    rbx
    push    rcx

    mov     rbx, rdi                ; RBX = Pin index

    ; Redirection register low dword offset = 0x10 + pin * 2
    shl     rdi, 1                  ; pin * 2
    add     rdi, 0x10               ; 0x10 + pin * 2
    mov     rcx, rdi                ; RCX = Register index

    call    ioapic_read             ; EAX = current low redirection dword

    and     eax, ~0x10000           ; Clear Bit 16 (Interrupt Mask Bit)

    mov     rdi, rcx                ; RDI = Register index
    mov     rsi, rax                ; RSI = updated value
    call    ioapic_write

    pop     rcx
    pop     rbx
    ret
IO_ENDFUNC ioapic_unmask_irq

%endif ; IO_INTR_IOAPIC_MASK_ASM
