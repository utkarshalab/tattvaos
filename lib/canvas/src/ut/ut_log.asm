; ============================================================================
; Utkarsha Log Service Binding — ut_log.asm
; Console/serial output
; ============================================================================

%define UT_BINDING_IMPL 1
%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"

section .text

; ---------------------------------------------------------------------------
; ut_log_write
;   Write bytes to console/serial (blocking but fast)
;   IN:  rdi = buffer pointer
;        rsi = length
;   OUT: rax = bytes written (== length on success), negative error
; ---------------------------------------------------------------------------
global ut_log_write
ut_log_write:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    mov rax, SYS_LOG_WRITE
    syscall
    EPILOGUE_RESTORE rbx, r12

; ---------------------------------------------------------------------------
; ut_log_printf
;   Write formatted (limited printf: %s %d %x %p %c %% )
;   IN:  rdi = format string, rsi... = args
;   OUT: rax = chars written
; ---------------------------------------------------------------------------
global ut_log_printf
ut_log_printf:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rax, SYS_LOG_PRINTF
    syscall
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15

; ---------------------------------------------------------------------------
; ut_log_set_level
;   Set log level filter
;   IN:  rdi = level (0=none, 1=error, 2=warn, 3=info, 4=debug, 5=trace)
; ---------------------------------------------------------------------------
global ut_log_set_level
ut_log_set_level:
    PROLOGUE
    mov rax, SYS_LOG_SET_LEVEL
    syscall
    EPILOGUE

; ---------------------------------------------------------------------------
; ut_log_get_level
;   Get current log level
;   OUT: rax = level
; ---------------------------------------------------------------------------
global ut_log_get_level
ut_log_get_level:
    PROLOGUE
    mov rax, SYS_LOG_GET_LEVEL
    syscall
    EPILOGUE

; ---------------------------------------------------------------------------
; ut_log_flush
;   Flush any buffered output
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global ut_log_flush
ut_log_flush:
    PROLOGUE
    mov rax, SYS_LOG_FLUSH
    syscall
    EPILOGUE

section .data

global ut_log_version
ut_log_version: dq 0x010000

section .note.ut_contract
    db "UT_LOG_CONTRACT", 0
