; ============================================================================
; Utkarsha Time Service Binding — ut_time.asm
; Monotonic clock, timers, TSC access
; ============================================================================

%define UT_BINDING_IMPL 1
%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"

section .text

; ---------------------------------------------------------------------------
; ut_time_now_ns
;   Current monotonic time in nanoseconds
;   OUT: rax = ns since boot (u64)
; ---------------------------------------------------------------------------
global ut_time_now_ns
ut_time_now_ns:
    PROLOGUE
    mov rax, SYS_TIME_NOW_NS
    syscall
    EPILOGUE

; ---------------------------------------------------------------------------
; ut_time_now_us
;   Current monotonic time in microseconds
;   OUT: rax = us since boot
; ---------------------------------------------------------------------------
global ut_time_now_us
ut_time_now_us:
    PROLOGUE
    mov rax, SYS_TIME_NOW_US
    syscall
    EPILOGUE

; ---------------------------------------------------------------------------
; ut_time_now_ms
;   Current monotonic time in milliseconds
;   OUT: rax = ms since boot
; ---------------------------------------------------------------------------
global ut_time_now_ms
ut_time_now_ms:
    PROLOGUE
    mov rax, SYS_TIME_NOW_MS
    syscall
    EPILOGUE

; ---------------------------------------------------------------------------
; ut_time_tsc
;   High-resolution timestamp (TSC-based)
;   OUT: rax = TSC ticks, rdx = TSC frequency (Hz, constant)
; ---------------------------------------------------------------------------
global ut_time_tsc
ut_time_tsc:
    PROLOGUE
    mov rax, SYS_TIME_TSC
    syscall
    EPILOGUE

; ---------------------------------------------------------------------------
; ut_time_sleep_ns
;   Sleep for duration (nanoseconds)
;   IN:  rdi = duration_ns
;   OUT: rax = 0 OK, EINTR if interrupted
; ---------------------------------------------------------------------------
global ut_time_sleep_ns
ut_time_sleep_ns:
    PROLOGUE
    mov rax, SYS_TIME_SLEEP_NS
    syscall
    EPILOGUE

; ---------------------------------------------------------------------------
; ut_time_sleep_until
;   Sleep until absolute deadline
;   IN:  rdi = deadline_ns (absolute monotonic time)
;   OUT: rax = 0 woke on time, ETIMEDOUT if past, EINTR if interrupted
; ---------------------------------------------------------------------------
global ut_time_sleep_until
ut_time_sleep_until:
    PROLOGUE
    mov rax, SYS_TIME_SLEEP_UNTIL
    syscall
    EPILOGUE

; ---------------------------------------------------------------------------
; ut_timer_register
;   Register one-shot timer
;   IN:  rdi = deadline_ns (absolute)
;        rsi = callback function pointer
;        rdx = user_data (opaque)
;   OUT: rax = timer_id (>0), negative error
; ---------------------------------------------------------------------------
global ut_timer_register
ut_timer_register:
    PROLOGUE_SAVE rbx, r12
    mov rax, SYS_TIMER_REGISTER
    syscall
    EPILOGUE_RESTORE rbx, r12

; ---------------------------------------------------------------------------
; ut_timer_cancel
;   Cancel a timer
;   IN:  rdi = timer_id
;   OUT: rax = 0 OK, EINVAL if not found
; ---------------------------------------------------------------------------
global ut_timer_cancel
ut_timer_cancel:
    PROLOGUE
    mov rax, SYS_TIMER_CANCEL
    syscall
    EPILOGUE

section .data

global ut_time_version
ut_time_version: dq 0x010000

section .note.ut_contract
    db "UT_TIME_CONTRACT", 0
