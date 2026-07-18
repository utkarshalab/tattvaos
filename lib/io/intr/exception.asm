; =============================================================================
; lib/io/intr/exception.asm
; Custom exception handlers and stack safety verification for lib/io.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_INTR_EXCEPTION_ASM
%define IO_INTR_EXCEPTION_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"
%include "lib/io/io.inc"

section .rodata
msg_df_overflow: db "DF: Interrupt Stack Table Overflow Detected!", 0

section .text

extern percpu_get
extern console_milestone
extern kernel_panic

; =============================================================================
; io_exception_df_handler — Custom Double Fault (#DF) handler
; Verifies stack pointer boundaries on exception entry.
; =============================================================================
global io_exception_df_handler
io_exception_df_handler:
    cli                             ; Clear interrupts

    ; 1. Retrieve the local core's percpu_t storage
    call    percpu_get
    test    rax, rax
    jz      .fallback_panic         ; If per-CPU storage not set up, direct panic

    ; 2. Fetch the logical IRQ stack bottom (lowest address of stack)
    mov     rcx, [rax + percpu_t.irq_stack]
    test    rcx, rcx
    jz      .fallback_panic

    ; 3. Read the stack pointer RSP at crash (pushed by CPU on DF stack)
    ; Double Fault pushes error code (at rsp) and RIP, CS, RFLAGS, RSP, SS.
    ; RSP at crash is at [rsp + 32] (error_code=0, rip=8, cs=16, rflags=24, rsp=32)
    mov     rdx, [rsp + 32]

    ; Check if crash RSP < irq_stack bottom
    cmp     rdx, rcx
    jl      .stack_overflow

    ; Check if crash RSP > irq_stack top (stack size is 8KB = 8192 bytes)
    add     rcx, 8192
    cmp     rdx, rcx
    jg      .stack_overflow

.fallback_panic:
    ; Standard Double Fault panic
    lea     rdi, [rel msg_df_overflow]
    mov     rsi, [rsp + 8]          ; Crash RIP
    call    kernel_panic

.stack_overflow:
    ; Log stack overflow milestone before halting
    lea     rdi, [rel msg_df_overflow]
    call    console_milestone

    ; Halt execution
.halt:
    hlt
    jmp     .halt

%endif ; IO_INTR_EXCEPTION_ASM
