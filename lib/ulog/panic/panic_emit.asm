; =============================================================================
; Tattva OS — lib/ulog/panic/panic_emit.asm
; =============================================================================
; What LOG_FATAL (via emit/emit_sync.asm) actually runs. No ring, no pool, no
; heap, no drain fiber — a direct synchronous write to serial, the same
; guarantee kernel/sched/fiber_supervisor.asm's crash handling already
; depends on today via a raw uart_print_str call. This is that same
; guarantee, now leveled and NMI-guarded instead of ad hoc.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_PANIC_PANIC_EMIT_ASM
%define LIB_ULOG_PANIC_PANIC_EMIT_ASM

[BITS 64]

section .text

; -----------------------------------------------------------------------------
; panic_emit — Input: RDI = level, RSI = module_id, RDX = msg_ptr
; Output: none. Silently drops the message only if the NMI reentrancy guard
; denies it — everything else about this path is unconditional.
; -----------------------------------------------------------------------------
global panic_emit
panic_emit:
    push rbx
    push r12
    push r13

    mov ebx, edi                     ; level
    mov r12, rsi                      ; module_id
    mov r13, rdx                        ; msg_ptr

    call panic_nmi_guard_enter
    test eax, eax
    jz .skip

    call panic_lock_acquire

    mov edi, ebx
    call text_render_level_prefix    ; e.g. "[FATAL] " — writes directly via uart

    mov eax, r12d
    call uart_print_hex32
    mov al, ' '
    call uart_putc

    mov rsi, r13
    call uart_print_str

    mov al, 0x0D
    call uart_putc
    mov al, 0x0A
    call uart_putc

    call panic_lock_release
    call panic_nmi_guard_exit

.skip:
    pop r13
    pop r12
    pop rbx
    ret

%endif ; LIB_ULOG_PANIC_PANIC_EMIT_ASM
