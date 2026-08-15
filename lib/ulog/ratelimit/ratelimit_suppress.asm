; =============================================================================
; Tattva OS — lib/ulog/ratelimit/ratelimit_suppress.asm
; =============================================================================
; The public entry point — printk_ratelimit(), exactly. A call site that
; wants protection against flooding (a flapping NIC, a retry loop) calls
; this before emitting; a suppressed call costs one hash and one window
; check, nothing more. Distinct from level_gate.asm's macros: this is an
; opt-in runtime check a caller adds deliberately, not something every
; LOG_* call pays for.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_RATELIMIT_RATELIMIT_SUPPRESS_ASM
%define LIB_ULOG_RATELIMIT_RATELIMIT_SUPPRESS_ASM

[BITS 64]

%include "lib/ulog/module_ids.inc"
%include "lib/ulog/level/level_defs.inc"

section .text

; -----------------------------------------------------------------------------
; ratelimit_should_emit — Input: RDI = module_id, RSI = msg_ptr
; Output: RAX = 1 emit it, 0 suppressed
;
; Usage:
;   mov rdi, MOD_UNET_CORE
;   mov rsi, msg_link_flap
;   call ratelimit_should_emit
;   test rax, rax
;   jz .skip_log
;   LOG_WARN MOD_UNET_CORE, msg_link_flap
; .skip_log:
; -----------------------------------------------------------------------------
global ratelimit_should_emit
ratelimit_should_emit:
    push rbx
    push r12

    mov rbx, rdi
    mov r12, rsi

    call mono_get_nanos
    mov rdx, rax
    mov rdi, rbx
    mov rsi, r12
    call ratelimit_window_check

    pop r12
    pop rbx
    ret

%endif ; LIB_ULOG_RATELIMIT_RATELIMIT_SUPPRESS_ASM
