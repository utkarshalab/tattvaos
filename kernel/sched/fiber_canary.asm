%ifndef GUARD_KERNEL_SCHED_FIBER_CANARY_ASM
%define GUARD_KERNEL_SCHED_FIBER_CANARY_ASM
; =============================================================================
; Tattva OS — kernel/sched/fiber_canary.asm
; =============================================================================
; Stack Smashing Protection & Canary Verification Engine.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "kernel/sched/fiber.inc"

section .text

; -----------------------------------------------------------------------------
; canary_generate — Generate a 64-bit random canary cookie for a fiber
; Input:  none
; Output: RAX = 64-bit secret canary cookie
; -----------------------------------------------------------------------------
canary_generate:
    rdtsc                           ; EDX:EAX = CPU timestamp counter
    shl rdx, 32
    or rax, rdx                     ; RAX = 64-bit TSC
    mov rdx, CANARY_DEFAULT_MAGIC
    xor rax, rdx                    ; RAX = TSC ^ CANARY_DEFAULT_MAGIC
    ret

; -----------------------------------------------------------------------------
; canary_plant — Plant canary cookies at stack boundary markers
; Input:  RDI = FCB pointer
; Output: none
; -----------------------------------------------------------------------------
canary_plant:
    push rbx
    push rdx

    call canary_generate
    mov [rdi + fcb_t.canary], rax   ; Store in FCB

    ; Plant canary at stack_bottom
    mov rbx, [rdi + fcb_t.stack_bottom]
    mov [rbx], rax

    ; Plant canary at top boundary marker (stack_top - 16)
    mov rdx, [rdi + fcb_t.stack_top]
    sub rdx, 16
    mov [rdx], rax

    pop rdx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; canary_verify — Verify canary integrity of a fiber stack
; Input:  RDI = FCB pointer
; Output: RAX = 1 if valid, 0 if corrupted/tampered
; -----------------------------------------------------------------------------
canary_verify:
    push rbx
    push rdx
    push rsi

    mov rsi, [rdi + fcb_t.canary]    ; Expected canary

    ; 1. Check stack_bottom canary
    mov rbx, [rdi + fcb_t.stack_bottom]
    mov rax, [rbx]
    cmp rax, rsi
    jne .corrupted

    ; 2. Check top boundary marker canary
    mov rdx, [rdi + fcb_t.stack_top]
    sub rdx, 16
    mov rax, [rdx]
    cmp rax, rsi
    jne .corrupted

    mov rax, 1                      ; Valid!
    jmp .done

.corrupted:
    ; Canary tampered! Stack smashing detected.
    mov rsi, msg_canary_corrupt
    call uart_print_str
    xor rax, rax

.done:
    pop rsi
    pop rdx
    pop rbx
    ret

section .data
msg_canary_corrupt: db '[SECURITY ALERT] Stack Canary Corrupted! Stack Smashing Detected.', 0x0D, 0x0A, 0

%endif ; GUARD_KERNEL_SCHED_FIBER_CANARY_ASM
