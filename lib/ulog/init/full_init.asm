; =============================================================================
; Tattva OS — lib/ulog/init/full_init.asm
; =============================================================================
; Called once from kernel/entry/init.asm, after lib/mem's heap and
; kernel/sched exist. Brings up every piece of ulog state that needs an
; allocator or a scheduler: the record pool, this (boot) core's ring, the
; sink registry with the always-on serial sink, and the drain daemon fiber —
; then flips mode_transition.asm's switch last, once everything it depends
; on is actually ready.
;
; AP cores brought up later during SMP bring-up each need their own
; log_ring_alloc_for_this_cpu call from kernel/arch's own bring-up path —
; not from here, since this runs once on the boot core. That's a follow-up
; wiring change in kernel/arch, out of scope for this sweep.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_INIT_FULL_INIT_ASM
%define LIB_ULOG_INIT_FULL_INIT_ASM

[BITS 64]

%include "lib/ulog/level/level_defs.inc"

section .text

; -----------------------------------------------------------------------------
; ulog_full_init — Output: RAX = 1 ok, 0 if a critical step failed
; -----------------------------------------------------------------------------
global ulog_full_init
ulog_full_init:
    call record_pool_init
    test rax, rax
    jz .fail

    call level_module_map_init
    call sink_registry_init
    call batch_reset

    call log_ring_alloc_for_this_cpu
    test rax, rax
    jz .fail

    mov rdi, serial_sink_write
    mov rsi, serial_sink_flush
    mov rdx, ulog_serial_sink_name
    mov cl, LVL_TRACE
    call sink_registry_add
    test rax, rax
    jz .fail

    call ulog_mode_transition_to_full

    call drain_fiber_start
    test rax, rax
    jz .fail

    mov rax, 1
    ret

.fail:
    xor rax, rax
    ret

section .rodata
ulog_serial_sink_name: db "serial", 0

%endif ; LIB_ULOG_INIT_FULL_INIT_ASM
