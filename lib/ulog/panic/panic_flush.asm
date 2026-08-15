; =============================================================================
; Tattva OS — lib/ulog/panic/panic_flush.asm
; =============================================================================
; Force-drains every core's ring before halt/reset — not just the panicking
; core's own. The drain fiber that normally does this may be the very thing
; that's dead, so this walks ulog_rings_by_cpu directly and writes each
; remaining record straight to serial, skipping batching, backpressure, and
; every sink but the one guaranteed to still work.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_PANIC_PANIC_FLUSH_ASM
%define LIB_ULOG_PANIC_PANIC_FLUSH_ASM

[BITS 64]

%include "lib/ulog/ulog.inc"
%include "lib/percpu.inc"

section .text

; -----------------------------------------------------------------------------
; panic_flush — drain and print every core's backlog, synchronously
; Input:  none
; Output: none
; -----------------------------------------------------------------------------
global panic_flush
panic_flush:
    push rbx
    push r12

    call panic_nmi_guard_enter
    test eax, eax
    jz .skip

    call panic_lock_acquire

    xor r12, r12

.cpu_loop:
    cmp r12, PERCPU_MAX_CORES
    jae .cpus_done

    mov rbx, [ulog_rings_by_cpu + r12 * 8]
    test rbx, rbx
    jz .next_cpu

    sub rsp, LOG_RECORD_SIZE

.drain_ring:
    mov rdi, rbx
    mov rsi, rsp
    call log_ring_pop
    test rax, rax
    jz .ring_drained

    movzx edi, byte [rsp + log_record_t.level]
    call text_render_level_prefix
    mov rsi, [rsp + log_record_t.msg_ptr]
    call uart_print_str
    mov al, 0x0D
    call uart_putc
    mov al, 0x0A
    call uart_putc
    jmp .drain_ring

.ring_drained:
    add rsp, LOG_RECORD_SIZE

.next_cpu:
    inc r12
    jmp .cpu_loop

.cpus_done:
    call panic_lock_release
    call panic_nmi_guard_exit

.skip:
    pop r12
    pop rbx
    ret

%endif ; LIB_ULOG_PANIC_PANIC_FLUSH_ASM
