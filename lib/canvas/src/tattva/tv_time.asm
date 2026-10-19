; ============================================================================
; Tattva Time Service Binding — tv_time.asm
; Monotonic clock, timers, TSC access
; ============================================================================

%define TATTVA_BINDING_IMPL 1
%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

section .text

; ---------------------------------------------------------------------------
; tv_time_now_ns
;   Current monotonic time in nanoseconds
;   OUT: rax = ns since boot (u64)
; ---------------------------------------------------------------------------
global tv_time_now_ns
tv_time_now_ns:
    PROLOGUE
    mov rax, SYS_TIME_NOW_NS
    syscall
    EPILOGUE

; ---------------------------------------------------------------------------
; tv_time_now_us
;   Current monotonic time in microseconds
;   OUT: rax = us since boot
; ---------------------------------------------------------------------------
global tv_time_now_us
tv_time_now_us:
    PROLOGUE
    mov rax, SYS_TIME_NOW_US
    syscall
    EPILOGUE

; ---------------------------------------------------------------------------
; tv_time_now_ms
;   Current monotonic time in milliseconds
;   OUT: rax = ms since boot
; ---------------------------------------------------------------------------
global tv_time_now_ms
tv_time_now_ms:
    PROLOGUE
    mov rax, SYS_TIME_NOW_MS
    syscall
    EPILOGUE

; ---------------------------------------------------------------------------
; tv_time_tsc
;   High-resolution timestamp (TSC-based)
;   OUT: rax = TSC ticks, rdx = TSC frequency (Hz, constant)
; ---------------------------------------------------------------------------
global tv_time_tsc
tv_time_tsc:
    PROLOGUE
    mov rax, SYS_TIME_TSC
    syscall
    EPILOGUE

; ---------------------------------------------------------------------------
; tv_time_sleep_ns
;   Sleep for duration (nanoseconds)
;   IN:  rdi = duration_ns
;   OUT: rax = 0 OK, EINTR if interrupted
; ---------------------------------------------------------------------------
global tv_time_sleep_ns
tv_time_sleep_ns:
    PROLOGUE
    mov rax, SYS_TIME_SLEEP_NS
    syscall
    EPILOGUE

; ---------------------------------------------------------------------------
; tv_time_sleep_until
;   Sleep until absolute deadline
;   IN:  rdi = deadline_ns (absolute monotonic time)
;   OUT: rax = 0 woke on time, ETIMEDOUT if past, EINTR if interrupted
; ---------------------------------------------------------------------------
global tv_time_sleep_until
tv_time_sleep_until:
    PROLOGUE
    mov rax, SYS_TIME_SLEEP_UNTIL
    syscall
    EPILOGUE

; ---------------------------------------------------------------------------
; tv_timer_register
;   Register one-shot timer
;   IN:  rdi = deadline_ns (absolute)
;        rsi = callback function pointer
;        rdx = user_data (opaque)
;   OUT: rax = timer_id (>0), negative error
; ---------------------------------------------------------------------------
global tv_timer_register
tv_timer_register:
    PROLOGUE_SAVE rbx, r12
    mov rax, SYS_TIMER_REGISTER
    syscall
    EPILOGUE_RESTORE rbx, r12

; ---------------------------------------------------------------------------
; tv_timer_cancel
;   Cancel a timer
;   IN:  rdi = timer_id
;   OUT: rax = 0 OK, EINVAL if not found
; ---------------------------------------------------------------------------
global tv_timer_cancel
tv_timer_cancel:
    PROLOGUE
    mov rax, SYS_TIMER_CANCEL
    syscall
    EPILOGUE

section .data

global tv_time_version
tv_time_version: dq 0x010000

section .note.tattva_contract
    db "TATTVA_TIME_CONTRACT", 0
