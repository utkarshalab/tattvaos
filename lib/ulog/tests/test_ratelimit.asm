; =============================================================================
; Tattva OS — lib/ulog/tests/test_ratelimit.asm
; =============================================================================
; Confirms a flooding call site gets suppressed after
; ULOG_RATELIMIT_MAX_PER_WINDOW admissions within one window, and that a
; different signature in the same window is unaffected.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_TESTS_TEST_RATELIMIT_ASM
%define LIB_ULOG_TESTS_TEST_RATELIMIT_ASM

[BITS 64]

%include "lib/ulog/config/defaults.inc"
%include "lib/ulog/module_ids.inc"

section .text

; -----------------------------------------------------------------------------
; ulog_test_ratelimit — Output: RAX = 0 pass, -1 fail
; -----------------------------------------------------------------------------
global ulog_test_ratelimit
ulog_test_ratelimit:
    push rbx
    push r12

    mov r12, ULOG_RATELIMIT_MAX_PER_WINDOW
.admit_loop:
    test r12, r12
    jz .admit_done
    mov rdi, MOD_UNET_CORE
    mov rsi, .msg_flood
    mov rdx, 1000                    ; a fixed "now" well inside one window
    call ratelimit_window_check
    test rax, rax
    jz .fail                         ; every admission up to the cap must succeed
    dec r12
    jmp .admit_loop

.admit_done:
    ; one more, in the same window, must be suppressed
    mov rdi, MOD_UNET_CORE
    mov rsi, .msg_flood
    mov rdx, 1000
    call ratelimit_window_check
    test rax, rax
    jnz .fail

    ; a different message at the same instant is a different bucket/signature
    ; and must be admitted regardless of the first signature's state
    mov rdi, MOD_UNET_CORE
    mov rsi, .msg_other
    mov rdx, 1000
    call ratelimit_window_check
    test rax, rax
    jz .fail

    xor rax, rax
    jmp .done

.fail:
    mov rax, -1

.done:
    pop r12
    pop rbx
    ret

section .rodata
.msg_flood: db "link flapped", 0
.msg_other: db "unrelated event", 0

%endif ; LIB_ULOG_TESTS_TEST_RATELIMIT_ASM
