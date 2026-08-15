; =============================================================================
; Tattva OS — lib/ulog/tests/test_sinks.asm
; =============================================================================
; sink_registry.asm's add/count/get, and sink_health.asm's three-condition
; check — enabled, healthy, and not mid-breaker-cooldown.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_TESTS_TEST_SINKS_ASM
%define LIB_ULOG_TESTS_TEST_SINKS_ASM

[BITS 64]

%include "lib/ulog/sinks/sink_iface.inc"
%include "lib/ulog/level/level_defs.inc"
%include "lib/ulog/config/defaults.inc"

section .text

; ---- a do-nothing write_fn/flush_fn pair, just to have valid pointers ------
test_sink_noop_write:
    mov rax, rsi
    ret
test_sink_noop_flush:
    mov rax, 1
    ret

; -----------------------------------------------------------------------------
; ulog_test_sinks — Output: RAX = 0 pass, -1 fail
; -----------------------------------------------------------------------------
global ulog_test_sinks
ulog_test_sinks:
    push rbx

    call sink_registry_init
    call sink_registry_count
    test rax, rax
    jnz .fail

    mov rdi, test_sink_noop_write
    mov rsi, test_sink_noop_flush
    mov rdx, .name
    mov cl, LVL_WARN
    call sink_registry_add
    test rax, rax
    jz .fail
    mov rbx, rax

    call sink_registry_count
    cmp rax, 1
    jne .fail

    xor rdi, rdi
    call sink_registry_get
    cmp rax, rbx
    jne .fail

    ; freshly added sink is healthy and writable
    mov rdi, rbx
    call sink_health_check
    test rax, rax
    jz .fail

    ; repeated failures trip the breaker; sink_health_check must then say no
    mov r8d, ULOG_BREAKER_TRIP_THRESHOLD
.fail_loop:
    test r8d, r8d
    jz .fail_loop_done
    mov rdi, rbx
    call sink_health_note_failure
    mov rdi, rbx
    call dispatch_circuit_breaker_note_failure
    dec r8d
    jmp .fail_loop
.fail_loop_done:

    mov rdi, rbx
    call sink_health_check
    test rax, rax
    jnz .fail                        ; must be refusing writes now

    xor rax, rax
    jmp .done

.fail:
    mov rax, -1

.done:
    pop rbx
    ret

section .rodata
.name: db "test-sink", 0

%endif ; LIB_ULOG_TESTS_TEST_SINKS_ASM
