; ============================================================================
; Panic Handlers — called from macros.inc assertions
; ============================================================================
; Listed with the bindings so the host suites can leave it out: they link their
; own in tests/host/ut_host.asm, which exit instead of stopping.

%define PANIC_IMPL 1
%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/ut.inc"

section .text

%macro PANIC_HANDLER 2                  ; name, message
global %1
%1:
    PROLOGUE
    lea rdi, [rel %2]
    mov rsi, %2_len
    call ut_log_write
    PANIC
%endmacro

PANIC_HANDLER panic_assert_failed, panic_msg_assert
PANIC_HANDLER panic_null_ptr, panic_msg_null
PANIC_HANDLER panic_unaligned, panic_msg_unaligned
PANIC_HANDLER panic_bounds, panic_msg_bounds
PANIC_HANDLER panic_oom, panic_msg_oom
PANIC_HANDLER panic_unreachable, panic_msg_unreach

section .rodata

panic_msg_assert:       db "PANIC: Assertion failed", 10
panic_msg_assert_len:   equ $ - panic_msg_assert
panic_msg_null:         db "PANIC: Null pointer dereference", 10
panic_msg_null_len:     equ $ - panic_msg_null
panic_msg_unaligned:    db "PANIC: Unaligned memory access", 10
panic_msg_unaligned_len: equ $ - panic_msg_unaligned
panic_msg_bounds:       db "PANIC: Bounds check failed", 10
panic_msg_bounds_len:   equ $ - panic_msg_bounds
panic_msg_oom:          db "PANIC: Out of memory", 10
panic_msg_oom_len:      equ $ - panic_msg_oom
panic_msg_unreach:      db "PANIC: Unreachable code reached", 10
panic_msg_unreach_len:  equ $ - panic_msg_unreach
