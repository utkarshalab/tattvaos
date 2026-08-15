; =============================================================================
; Tattva OS — lib/ulog/sinks/sink_registry.asm
; =============================================================================
; The pluggable half of "pluggable sink": registration and iteration.
; drain/dispatch.asm is the only real reader; init/full_init.asm registers
; the always-on serial sink, and a future obs/udash would register its own
; live-tail sink through the same call.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_SINKS_SINK_REGISTRY_ASM
%define LIB_ULOG_SINKS_SINK_REGISTRY_ASM

[BITS 64]

%include "lib/ulog/sinks/sink_iface.inc"

section .bss
alignb 8
global ulog_sinks
ulog_sinks: resb (SINK_T_SIZE * ULOG_MAX_SINKS)
global ulog_sink_count
ulog_sink_count: resd 1

section .text

; -----------------------------------------------------------------------------
; sink_registry_init
; -----------------------------------------------------------------------------
global sink_registry_init
sink_registry_init:
    mov dword [ulog_sink_count], 0
    ret

; -----------------------------------------------------------------------------
; sink_registry_add
; Input:  RDI = write_fn, RSI = flush_fn, RDX = name_ptr, CL = min_level
; Output: RAX = sink_t* (0 if ULOG_MAX_SINKS already reached)
; -----------------------------------------------------------------------------
global sink_registry_add
sink_registry_add:
    push rbx
    push rcx

    mov ecx, [ulog_sink_count]
    cmp ecx, ULOG_MAX_SINKS
    jae .full

    mov rbx, SINK_T_SIZE
    imul rbx, rcx
    add rbx, ulog_sinks

    mov [rbx + sink_t.write_fn], rdi
    mov [rbx + sink_t.flush_fn], rsi
    mov [rbx + sink_t.name_ptr], rdx
    pop rcx                          ; recover caller's CL (min_level) — pushed above
    mov [rbx + sink_t.min_level], cl
    push rcx
    mov byte [rbx + sink_t.enabled], 1
    mov byte [rbx + sink_t.healthy], 1
    mov byte [rbx + sink_t.breaker_open], 0
    mov dword [rbx + sink_t.fail_count], 0
    mov qword [rbx + sink_t.breaker_trip_ns], 0

    inc dword [ulog_sink_count]
    mov rax, rbx
    jmp .done

.full:
    xor rax, rax

.done:
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; sink_registry_count — Output: RAX = number of registered sinks
; -----------------------------------------------------------------------------
global sink_registry_count
sink_registry_count:
    movsxd rax, dword [ulog_sink_count]
    ret

; -----------------------------------------------------------------------------
; sink_registry_get — Input: RDI = index. Output: RAX = sink_t* (0 if OOB)
; -----------------------------------------------------------------------------
global sink_registry_get
sink_registry_get:
    cmp edi, [ulog_sink_count]
    jae .oob

    mov rax, SINK_T_SIZE
    imul rax, rdi
    add rax, ulog_sinks
    ret

.oob:
    xor rax, rax
    ret

%endif ; LIB_ULOG_SINKS_SINK_REGISTRY_ASM
