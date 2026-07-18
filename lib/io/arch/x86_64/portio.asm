; =============================================================================
; lib/io/arch/x86_64/portio.asm
; Low-level assembly port I/O wrappers.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_ARCH_PORTIO_ASM
%define IO_ARCH_PORTIO_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"

section .text

; =============================================================================
; port_in8 — Read 1 byte from an x86 hardware I/O port
; In : RDI = Port Address (16-bit)
; Out: RAX = Byte read
; RSO: RDX scratch (saved); RAX owned-out
; =============================================================================
IO_FUNC port_in8
    push    rdx
    mov     rdx, rdi
    xor     rax, rax
    in      al, dx
    pop     rdx
    ret
IO_ENDFUNC port_in8

; =============================================================================
; port_out8 — Write 1 byte to an x86 hardware I/O port
; In : RDI = Port Address (16-bit), RSI = Byte to write (8-bit)
; RSO: RDX, RAX scratch (saved)
; =============================================================================
IO_FUNC port_out8
    push    rdx
    push    rax
    mov     rdx, rdi
    mov     rax, rsi
    out     dx, al
    pop     rax
    pop     rdx
    ret
IO_ENDFUNC port_out8

%endif ; IO_ARCH_PORTIO_ASM
