; ============================================================================
; Time Helpers — Wrappers around tv_time
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/tattva.inc"

section .text

global time_now_ns
time_now_ns:
    PROLOGUE
    call tv_time_now_ns
    ret

global time_now_us
time_now_us:
    PROLOGUE
    call tv_time_now_us
    ret

global time_now_ms
time_now_ms:
    PROLOGUE
    call tv_time_now_ms
    ret

global time_tsc
time_tsc:
    PROLOGUE
    call tv_time_tsc
    ret

global time_sleep_ns
time_sleep_ns:
    PROLOGUE
    call tv_time_sleep_ns
    ret

global time_sleep_until
time_sleep_until:
    PROLOGUE
    call tv_time_sleep_until
    ret

global timer_register
timer_register:
    PROLOGUE
    call tv_timer_register
    ret

global timer_cancel
timer_cancel:
    PROLOGUE
    call tv_timer_cancel
    ret

section .data
global time_version
time_version: dq 0x010000