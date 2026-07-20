; =============================================================================
; Tattva OS â€” kernel/entry/main.asm
; =============================================================================
; Kernel main entry point. Invoked after subsystem initialization completes.
; Prints the final kernel ready message and transitions to the CPU idle loop.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

section .text

extern uart_print_str
extern run_all_memory_tests

global kernel_main

kernel_main:
    ; 1. Print kernel execution ready state
    mov rsi, msg_kernel_ready
    call uart_print_str

    call run_all_memory_tests

.idle:
    ; 4. Disable interrupts (no external interrupt handlers registered yet)
    cli

    ; 5. Enter CPU idle loop
.idle_loop:
    hlt                             ; halt the processor until next interrupt
    jmp .idle_loop                  ; jump back if an NMI or interrupt wakes us

; -----------------------------------------------------------------------------
; Messages
; -----------------------------------------------------------------------------
section .data

msg_kernel_ready:     db 'Tattva Kernel Ready. Entering main execution.', 0x0D, 0x0A, 0

