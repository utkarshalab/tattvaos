; =============================================================================
; lib/io/intr/tss.asm
; x86_64 Task State Segment (TSS) & Interrupt Stack Table (IST) helper.
;
; Implements TSS structure formatting and Task Register (TR) loading. This
; enables hardware-level safe stack switching during critical exceptions.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_INTR_TSS_ASM
%define IO_INTR_TSS_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"
%include "lib/io/io.inc"

section .text

global io_init_tss

; =============================================================================
; io_init_tss — Zero-initialize TSS structure and load Task Register selector
; In : RDI = -> 104-byte TSS buffer (caller provided)
;      RSI = Clean stack pointer for IST1 (Double Fault stack base)
;      RDX = GDT selector offset for the TSS descriptor (e.g. 0x28)
; =============================================================================
IO_FUNC io_init_tss
    guard_null rdi
    guard_null rsi

    push    rdi
    push    rcx

    ; 1. Zero out the 104-byte TSS structure
    mov     rcx, 13                 ; 13 qwords = 104 bytes
    xor     rax, rax
    rep     stosq
    pop     rdi                     ; Restore RDI pointer

    ; 2. Configure IST1 Stack Pointer (offset 36 in TSS)
    mov     [rdi + 36], rsi

    ; 3. Configure I/O Map Base Address beyond TSS limit (offset 102 = 104)
    ;    This prevents user mode task I/O port permission faults scanning
    mov     word [rdi + 102], 104

    ; 4. Load Task Register (LTR) with the GDT TSS Selector
    mov     rax, rdx
    ltr     ax                      ; Load Task Register

    pop     rcx
    ret
IO_ENDFUNC io_init_tss

%endif ; IO_INTR_TSS_ASM
