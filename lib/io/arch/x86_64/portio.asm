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
IO_ENDFUNC port_out8

global port_in16
global port_out16
global port_in32
global port_out32

; =============================================================================
; port_in16 — Read 2 bytes (word) from an x86 hardware I/O port
; In : RDI = Port Address (16-bit)
; Out: RAX = Word read (16-bit)
; =============================================================================
IO_FUNC port_in16
    push    rdx
    mov     rdx, rdi
    xor     rax, rax
    in      ax, dx
    pop     rdx
IO_ENDFUNC port_in16

; =============================================================================
; port_out16 — Write 2 bytes (word) to an x86 hardware I/O port
; In : RDI = Port Address (16-bit), RSI = Word to write (16-bit)
; =============================================================================
IO_FUNC port_out16
    push    rdx
    push    rax
    mov     rdx, rdi
    mov     rax, rsi
    out     dx, ax
    pop     rax
    pop     rdx
IO_ENDFUNC port_out16

; =============================================================================
; port_in32 — Read 4 bytes (double-word) from an x86 hardware I/O port
; In : RDI = Port Address (16-bit)
; Out: RAX = Double-word read (32-bit)
; =============================================================================
IO_FUNC port_in32
    push    rdx
    mov     rdx, rdi
    xor     rax, rax
    in      eax, dx
    pop     rdx
IO_ENDFUNC port_in32

; =============================================================================
; port_out32 — Write 4 bytes (double-word) to an x86 hardware I/O port
; In : RDI = Port Address (16-bit), RSI = Double-word to write (32-bit)
; =============================================================================
IO_FUNC port_out32
    push    rdx
    push    rax
    mov     rdx, rdi
    mov     rax, rsi
    out     dx, eax
    pop     rax
    pop     rdx
IO_ENDFUNC port_out32

%endif ; IO_ARCH_PORTIO_ASM
