; =============================================================================
; Tattva OS — lib/ulog/drain/dispatch_circuit_breaker.asm
; =============================================================================
; A sink that keeps failing (disk full, link down) stops being hammered.
; Trips open after ULOG_BREAKER_TRIP_THRESHOLD consecutive failures; a
; half-open retry is allowed once ULOG_BREAKER_COOLDOWN_NANOS has passed —
; the next write attempt is that test, and its result decides whether the
; breaker closes again or resets the cooldown.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_DRAIN_DISPATCH_CIRCUIT_BREAKER_ASM
%define LIB_ULOG_DRAIN_DISPATCH_CIRCUIT_BREAKER_ASM

[BITS 64]

%include "lib/ulog/sinks/sink_iface.inc"
%include "lib/ulog/config/defaults.inc"

section .text

; -----------------------------------------------------------------------------
; dispatch_circuit_breaker_note_failure — Input: RDI = sink_t*
; Trips the breaker once fail_count (already bumped by sink_health.asm)
; crosses the threshold.
; -----------------------------------------------------------------------------
global dispatch_circuit_breaker_note_failure
dispatch_circuit_breaker_note_failure:
    push rax

    mov eax, [rdi + sink_t.fail_count]
    cmp eax, ULOG_BREAKER_TRIP_THRESHOLD
    jl .done

    mov byte [rdi + sink_t.breaker_open], 1
    push rdi
    call mono_get_nanos
    pop rdi
    mov [rdi + sink_t.breaker_trip_ns], rax

.done:
    pop rax
    ret

; -----------------------------------------------------------------------------
; dispatch_circuit_breaker_note_success — Input: RDI = sink_t*
; -----------------------------------------------------------------------------
global dispatch_circuit_breaker_note_success
dispatch_circuit_breaker_note_success:
    mov byte [rdi + sink_t.breaker_open], 0
    ret

; -----------------------------------------------------------------------------
; dispatch_circuit_breaker_maybe_close — called once per drain pass per sink
; Input:  RDI = sink_t*
; Output: none. Half-opens (clears breaker_open, resets fail_count) once
;         ULOG_BREAKER_COOLDOWN_NANOS has passed since the trip, giving the
;         next real write a chance to prove the sink recovered.
; -----------------------------------------------------------------------------
global dispatch_circuit_breaker_maybe_close
dispatch_circuit_breaker_maybe_close:
    push rbx
    push rax

    mov bl, [rdi + sink_t.breaker_open]
    test bl, bl
    jz .done

    push rdi
    call mono_get_nanos
    pop rdi

    sub rax, [rdi + sink_t.breaker_trip_ns]
    cmp rax, ULOG_BREAKER_COOLDOWN_NANOS
    jl .done

    mov byte [rdi + sink_t.breaker_open], 0
    mov dword [rdi + sink_t.fail_count], 0

.done:
    pop rax
    pop rbx
    ret

%endif ; LIB_ULOG_DRAIN_DISPATCH_CIRCUIT_BREAKER_ASM
