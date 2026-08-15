; =============================================================================
; Tattva OS — lib/ulog/panic/panic_nmi_safe.asm
; =============================================================================
; Guarantees panic_emit.asm can't deadlock or infinitely recurse — the exact
; constraint Linux's emergency console is built around. A per-core reentrancy
; counter, bounded: if logging the panic itself faults (a corrupt stack, a
; bad pointer in the message), the guard denies further attempts past
; PANIC_MAX_REENTRY instead of spinning forever inside a fault handler.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_PANIC_PANIC_NMI_SAFE_ASM
%define LIB_ULOG_PANIC_PANIC_NMI_SAFE_ASM

[BITS 64]

%include "lib/percpu.inc"

%define PANIC_MAX_REENTRY  3

section .bss
alignb 4
global panic_nmi_depth
panic_nmi_depth: resd PERCPU_MAX_CORES

section .text

; -----------------------------------------------------------------------------
; panic_nmi_guard_enter — Output: RAX = 1 ok to proceed, 0 too deep, bail
; -----------------------------------------------------------------------------
global panic_nmi_guard_enter
panic_nmi_guard_enter:
    push rbx

    mov eax, [gs:percpu_t.cpu_id]
    lea rbx, [panic_nmi_depth + rax * 4]
    mov eax, [rbx]
    cmp eax, PANIC_MAX_REENTRY
    jae .deny

    inc dword [rbx]
    mov eax, 1
    jmp .done

.deny:
    xor eax, eax

.done:
    pop rbx
    ret

; -----------------------------------------------------------------------------
; panic_nmi_guard_exit — pair with a successful panic_nmi_guard_enter
; -----------------------------------------------------------------------------
global panic_nmi_guard_exit
panic_nmi_guard_exit:
    push rax
    push rbx

    mov eax, [gs:percpu_t.cpu_id]
    lea rbx, [panic_nmi_depth + rax * 4]
    dec dword [rbx]

    pop rbx
    pop rax
    ret

%endif ; LIB_ULOG_PANIC_PANIC_NMI_SAFE_ASM
