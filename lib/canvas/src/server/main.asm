; ============================================================================
; Canvas Server Entry Point — main.asm
; Called by Utkarsha loader as canvasd_init
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"

section .text

; ---------------------------------------------------------------------------
; canvasd_init
;   Main entry point for Canvas display server
;   Called by Utkarsha loader after kernel init
;   IN:  rdi = boot_info pointer (Utkarsha boot info struct)
;   OUT: rax = 0 on success, negative error (never returns on success)
; ---------------------------------------------------------------------------
global canvasd_init
canvasd_init:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15

    ; Save boot info pointer
    mov rbx, rdi

    ; Initialize logging first (for early debug output)
    mov rdi, LOG_DEBUG
    call ut_log_set_level

    ; Print banner
    mov rdi, banner_msg
    mov rsi, banner_len
    call ut_log_write

    ; Initialize entropy (for capability tokens)
    call init_entropy

    ; Initialize memory arena for server
    call init_server_arena

    ; Initialize waitset for event loop
    call init_waitset

    ; Initialize Utkarsha service bindings
    call init_ut_bindings

    ; Initialize protocol layer (C4)
    call init_protocol

    ; Initialize server core (C5)
    call init_server_core

    ; Initialize backends (C9)
    call init_backends

    ; Initialize outputs (C11)
    call init_outputs

    ; Initialize input (C12)
    call init_input

    ; Initialize shell/policy (C13)
    call init_shell

    ; Main event loop
    call event_loop

    ; Should never reach here
    UNREACHABLE

; ---------------------------------------------------------------------------
; Initialization stages
; ---------------------------------------------------------------------------

init_entropy:
    PROLOGUE
    ; Get siphash key for capability tokens
    sub rsp, 32
    mov rdi, rsp
    call ut_entropy_siphash_key
    add rsp, 32
    leave
    ret

init_server_arena:
    PROLOGUE
    ; Allocate 16MB global arena
    mov rdi, 16 * 1024 * 1024
    mov rsi, MEM_DMA
    call ut_mem_alloc
    test rax, rax
    js .oom
    ; Store arena base in global
    mov [global_arena_base], rax
    mov [global_arena_cursor], rax
    mov [global_arena_limit], rax
    add qword [global_arena_limit], 16 * 1024 * 1024
    leave
    ret
.oom:
    mov rdi, panic_oom_msg
    mov rsi, panic_oom_len
    call ut_log_write
    PANIC

init_waitset:
    PROLOGUE
    call ut_waitset_create
    test rax, rax
    js .fail
    mov [main_waitset], rax
    leave
    ret
.fail:
    mov rdi, panic_waitset_msg
    mov rsi, panic_waitset_len
    call ut_log_write
    PANIC

init_ut_bindings:
    PROLOGUE
    ; Verify Utkarsha contract version
    leave
    ret

init_protocol:
    PROLOGUE
    leave
    ret

init_server_core:
    PROLOGUE
    leave
    ret

init_backends:
    PROLOGUE
    leave
    ret

init_outputs:
    PROLOGUE
    leave
    ret

init_input:
    PROLOGUE
    leave
    ret

init_shell:
    PROLOGUE
    leave
    ret

; ---------------------------------------------------------------------------
; Event Loop
; ---------------------------------------------------------------------------
event_loop:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15

.loop:
    ; Wait for events (infinite wait)
    mov rdi, [main_waitset]
    mov rsi, 0          ; infinite timeout
    call ut_wait_wait

    test rax, rax
    js .error

    ; Check event types and dispatch
    test rax, WAIT_IRQ
    jnz .handle_irq

    test rax, WAIT_CHANNEL
    jnz .handle_channel

    test rax, WAIT_TIMER
    jnz .handle_timer

    test rax, WAIT_INPUT
    jnz .handle_input

    jmp .loop

.handle_irq:
    call dispatch_irq
    jmp .loop

.handle_channel:
    call dispatch_channel
    jmp .loop

.handle_timer:
    call dispatch_timer
    jmp .loop

.handle_input:
    call dispatch_input
    jmp .loop

.error:
    ; Log error and continue
    jmp .loop

dispatch_irq:
    ret

dispatch_channel:
    ret

dispatch_timer:
    ret

dispatch_input:
    ret

section .rodata

banner_msg:     db "Canvas Display Server for Utkarsha OS", 10, 0
banner_len:     equ $ - banner_msg

panic_oom_msg:  db "PANIC: Failed to allocate server arena", 10, 0
panic_oom_len:  equ $ - panic_oom_msg

panic_waitset_msg: db "PANIC: Failed to create main waitset", 10, 0
panic_waitset_len: equ $ - panic_waitset_msg

section .bss

global_arena_base:    resq 1
global_arena_cursor:  resq 1
global_arena_limit:   resq 1
main_waitset:         resq 1

section .data

global canvasd_version
canvasd_version: dq 0x00010000   ; 0.1.0
