; ============================================================================
; Log — Leveled Logger (wraps ut_log)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/ut.inc"

section .text

global log_init
log_init:
    PROLOGUE
    xor rax, rax
    leave
    ret

global log_set_level
log_set_level:
    PROLOGUE
    call ut_log_set_level
    leave
    ret

global log_error
log_error:
    PROLOGUE
    cmp qword [log_level], 1
    jl .done
    mov rdi, rsi
    mov rsi, rdx
    call ut_log_write
.done:
    leave
    ret

global log_warn
log_warn:
    PROLOGUE
    cmp qword [log_level], 2
    jl .done
    mov rdi, rsi
    mov rsi, rdx
    call ut_log_write
.done:
    leave
    ret

global log_info
log_info:
    PROLOGUE
    cmp qword [log_level], 3
    jl .done
    mov rdi, rsi
    mov rsi, rdx
    call ut_log_write
.done:
    leave
    ret

global log_debug
log_debug:
    PROLOGUE
    cmp qword [log_level], 4
    jl .done
    mov rdi, rsi
    mov rsi, rdx
    call ut_log_write
.done:
    leave
    ret

section .bss
log_level: resq 1

section .data
global log_version
log_version: dq 0x010000
