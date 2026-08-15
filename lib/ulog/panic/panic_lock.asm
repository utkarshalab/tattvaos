; =============================================================================
; Tattva OS — lib/ulog/panic/panic_lock.asm
; =============================================================================
; Serializes panic output across cores when more than one crashes at once —
; real on SMP, not hypothetical. Deliberately NOT a normal spinlock: a
; standard spin-forever lock is itself an NMI-safety hazard if the core
; holding it is the one that's dead. This gives up after a bounded spin and
; lets the caller proceed unlocked — a torn panic message beats no message.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_PANIC_PANIC_LOCK_ASM
%define LIB_ULOG_PANIC_PANIC_LOCK_ASM

[BITS 64]

%define PANIC_LOCK_SPIN_LIMIT  100000

section .bss
alignb 4
global ulog_panic_lock
ulog_panic_lock: resd 1

section .text

; -----------------------------------------------------------------------------
; panic_lock_acquire — best-effort mutual exclusion, bounded wait
; -----------------------------------------------------------------------------
global panic_lock_acquire
panic_lock_acquire:
    push rax
    push rcx
    push rdx

    xor ecx, ecx

.try:
    xor eax, eax
    mov edx, 1
    lock cmpxchg [ulog_panic_lock], edx
    jz .done                         ; acquired

    inc ecx
    cmp ecx, PANIC_LOCK_SPIN_LIMIT
    jae .done                        ; give up waiting, proceed unlocked

    pause
    jmp .try

.done:
    pop rdx
    pop rcx
    pop rax
    ret

; -----------------------------------------------------------------------------
; panic_lock_release
; -----------------------------------------------------------------------------
global panic_lock_release
panic_lock_release:
    mov dword [ulog_panic_lock], 0
    ret

%endif ; LIB_ULOG_PANIC_PANIC_LOCK_ASM
