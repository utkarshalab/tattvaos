; ============================================================================
; Tattva Log Service Binding — tv_log.asm
; Console/serial output, panic handlers
; ============================================================================

%define TATTVA_BINDING_IMPL 1
%define PANIC_IMPL 1
%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

section .text

; ---------------------------------------------------------------------------
; tv_log_write
;   Write bytes to console/serial (blocking but fast)
;   IN:  rdi = buffer pointer
;        rsi = length
;   OUT: rax = bytes written (== length on success), negative error
; ---------------------------------------------------------------------------
global tv_log_write
tv_log_write:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    mov rax, SYS_LOG_WRITE
    syscall
    EPILOGUE_RESTORE rbx, r12

; ---------------------------------------------------------------------------
; tv_log_printf
;   Write formatted (limited printf: %s %d %x %p %c %% )
;   IN:  rdi = format string, rsi... = args
;   OUT: rax = chars written
; ---------------------------------------------------------------------------
global tv_log_printf
tv_log_printf:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rax, SYS_LOG_PRINTF
    syscall
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15

; ---------------------------------------------------------------------------
; tv_log_set_level
;   Set log level filter
;   IN:  rdi = level (0=none, 1=error, 2=warn, 3=info, 4=debug, 5=trace)
; ---------------------------------------------------------------------------
global tv_log_set_level
tv_log_set_level:
    PROLOGUE
    mov rax, SYS_LOG_SET_LEVEL
    syscall
    EPILOGUE

; ---------------------------------------------------------------------------
; tv_log_get_level
;   Get current log level
;   OUT: rax = level
; ---------------------------------------------------------------------------
global tv_log_get_level
tv_log_get_level:
    PROLOGUE
    mov rax, SYS_LOG_GET_LEVEL
    syscall
    EPILOGUE

; ---------------------------------------------------------------------------
; tv_log_flush
;   Flush any buffered output
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global tv_log_flush
tv_log_flush:
    PROLOGUE
    mov rax, SYS_LOG_FLUSH
    syscall
    EPILOGUE

; ---------------------------------------------------------------------------
; Panic Handlers (called from macros.inc assertions)
; ---------------------------------------------------------------------------

global panic_assert_failed
panic_assert_failed:
    PROLOGUE
    ; Print assertion failure message
    mov rdi, panic_msg_assert
    mov rsi, panic_msg_assert_len
    call tv_log_write
    ; Dump registers
    call dump_registers
    PANIC

global panic_null_ptr
panic_null_ptr:
    PROLOGUE
    mov rdi, panic_msg_null
    mov rsi, panic_msg_null_len
    call tv_log_write
    call dump_registers
    PANIC

global panic_unaligned
panic_unaligned:
    PROLOGUE
    mov rdi, panic_msg_unaligned
    mov rsi, panic_msg_unaligned_len
    call tv_log_write
    call dump_registers
    PANIC

global panic_bounds
panic_bounds:
    PROLOGUE
    mov rdi, panic_msg_bounds
    mov rsi, panic_msg_bounds_len
    call tv_log_write
    call dump_registers
    PANIC

global panic_oom
panic_oom:
    PROLOGUE
    mov rdi, panic_msg_oom
    mov rsi, panic_msg_oom_len
    call tv_log_write
    call dump_registers
    PANIC

global panic_unreachable
panic_unreachable:
    PROLOGUE
    mov rdi, panic_msg_unreach
    mov rsi, panic_msg_unreach_len
    call tv_log_write
    call dump_registers
    PANIC

; ---------------------------------------------------------------------------
; Register Dump Helper
; ---------------------------------------------------------------------------
dump_registers:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    ; Print each register
    mov rdi, reg_dump_fmt
    mov rsi, rax
    mov rdx, rbx
    mov rcx, rcx
    mov r8, rdx
    mov r9, rsi
    mov r10, rdi
    mov r11, rbp
    mov r12, rsp
    mov r13, r8
    mov r14, r9
    mov r15, r10
    call tv_log_printf
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

section .rodata

panic_msg_assert:       db "PANIC: Assertion failed", 10, 0
panic_msg_assert_len:   equ $ - panic_msg_assert
panic_msg_null:         db "PANIC: Null pointer dereference", 10, 0
panic_msg_null_len:     equ $ - panic_msg_null
panic_msg_unaligned:    db "PANIC: Unaligned memory access", 10, 0
panic_msg_unaligned_len: equ $ - panic_msg_unaligned
panic_msg_bounds:       db "PANIC: Bounds check failed", 10, 0
panic_msg_bounds_len:   equ $ - panic_msg_bounds
panic_msg_oom:          db "PANIC: Out of memory", 10, 0
panic_msg_oom_len:      equ $ - panic_msg_oom
panic_msg_unreach:      db "PANIC: Unreachable code reached", 10, 0
panic_msg_unreach_len:  equ $ - panic_msg_unreach

reg_dump_fmt:           db "RAX=%p RBX=%p RCX=%p RDX=%p RSI=%p RDI=%p RBP=%p RSP=%p R8=%p R9=%p R10=%p R11=%p R12=%p R13=%p R14=%p R15=%p", 10, 0

section .data

global tv_log_version
tv_log_version: dq 0x010000

section .note.tattva_contract
    db "TATTVA_LOG_CONTRACT", 0
