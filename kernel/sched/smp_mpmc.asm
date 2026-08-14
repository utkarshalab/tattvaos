%ifndef GUARD_KERNEL_SCHED_SMP_MPMC_ASM
%define GUARD_KERNEL_SCHED_SMP_MPMC_ASM
; =============================================================================
; Tattva OS — kernel/sched/smp_mpmc.asm
; =============================================================================
; Lock-Free Multi-Producer Multi-Consumer (MPMC) Queue for SMP Work Stealing.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "kernel/sched/fiber.inc"

section .text

; -----------------------------------------------------------------------------
; smp_mpmc_push — Lock-free push FCB pointer into multi-core MPMC queue
; Input:  RDI = FCB pointer
; Output: RAX = 1 if successful, 0 if queue full
; -----------------------------------------------------------------------------
smp_mpmc_push:
    push rbx
    push rcx
    push rdx
    push rsi

    mov rsi, rdi                    ; RSI = element to push

.retry:
    mov rax, [mpmc_tail]            ; RAX = current tail index
    mov rbx, rax
    inc rbx
    and rbx, (FIBER_MAX_COUNT - 1)   ; RBX = next tail index

    mov rcx, [mpmc_head]            ; RCX = current head index
    cmp rbx, rcx
    je .full                        ; Queue full

    ; Attempt atomic CAS (Compare-And-Swap) on mpmc_tail
    ; lock cmpxchg [mpmc_tail], rbx
    mov rdx, rax
    mov rax, rdx
    lock cmpxchg [mpmc_tail], rbx
    jnz .retry                      ; If CAS failed, retry

    ; Successfully reserved slot at index rdx! Store element.
    imul rdx, 8
    mov [mpmc_buffer + rdx], rsi
    mov rax, 1
    jmp .done

.full:
    xor rax, rax

.done:
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; smp_mpmc_pop — Lock-free pop FCB pointer from multi-core MPMC queue
; Input:  none
; Output: RAX = FCB pointer (or 0 if queue empty)
; -----------------------------------------------------------------------------
smp_mpmc_pop:
    push rbx
    push rcx
    push rdx

.retry:
    mov rax, [mpmc_head]            ; RAX = current head index
    mov rbx, [mpmc_tail]            ; RBX = current tail index
    cmp rax, rbx
    je .empty                       ; Queue empty

    mov rdx, rax
    inc rdx
    and rdx, (FIBER_MAX_COUNT - 1)   ; RDX = next head index

    ; Attempt atomic CAS on mpmc_head
    lock cmpxchg [mpmc_head], rdx
    jnz .retry                      ; If CAS failed, retry

    ; Successfully reserved head slot RAX! Read element.
    imul rax, 8
    mov rax, [mpmc_buffer + rax]
    jmp .done

.empty:
    xor rax, rax

.done:
    pop rdx
    pop rcx
    pop rbx
    ret

section .data
align 64
mpmc_buffer: times FIBER_MAX_COUNT dq 0
mpmc_head:   dq 0
mpmc_tail:   dq 0

%endif ; GUARD_KERNEL_SCHED_SMP_MPMC_ASM
