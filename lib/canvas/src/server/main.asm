; ============================================================================
; Canvas Server Entry Point — main.asm
; The program's entry point, canvasd_init
; ============================================================================
; Startup and requests are in server_core.asm. Accepting clients on a real
; channel waits for the kernel's channels and handle passing (KRN-03, KRN-04).

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/backend.inc"
%include "inc/struct_offsets.inc"

default rel

extern arena_init
extern greeter_start
extern greeter_step
extern taskbar_start
extern taskbar_step
extern input_repeat_deadline
extern server_init
extern server_poll

%define SERVER_ARENA_BYTES  (16 * 1024 * 1024)
%define DEFAULT_WIDTH       1280
%define DEFAULT_HEIGHT      800

; What ut_fb_info fills
%define FB_INFO_BASE        0
%define FB_INFO_WIDTH       8
%define FB_INFO_HEIGHT      12
%define FB_INFO_PITCH       16
%define FB_INFO_FORMAT      20
%define FB_INFO_SIZE        24
%define FB_INFO_BYTES       32

section .text

; ---------------------------------------------------------------------------
; canvasd_init
;   Main entry point for Canvas display server
;   IN:  rdi = the program's start block (unused)
;   OUT: rax = negative error (never returns on success)
; ---------------------------------------------------------------------------
global canvasd_init
canvasd_init:
    PROLOGUE_SAVE rbx, r12, r13
    sub rsp, FB_INFO_BYTES + 8

    ; Logging first, for early debug output
    mov rdi, LOG_DEBUG
    call ut_log_set_level
    lea rdi, [banner_msg]
    mov rsi, banner_len
    call ut_log_write

    ; The server's arena
    mov edi, SERVER_ARENA_BYTES
    xor esi, esi
    call ut_mem_alloc
    test rax, rax
    js .no_arena
    lea rdi, [server_arena]
    mov rsi, rax
    mov edx, SERVER_ARENA_BYTES
    call arena_init

    ; The kernel's framebuffer if it has one, else headless
    xor r13d, r13d
    mov rdi, rsp
    call ut_fb_info
    test rax, rax
    js .start
    mov rax, [rsp + FB_INFO_BASE]
    test rax, rax
    jz .start
    mov [fb_config + Config.fb_base], rax
    mov rax, [rsp + FB_INFO_SIZE]
    mov [fb_config + Config.fb_size], rax
    mov eax, [rsp + FB_INFO_WIDTH]
    mov [fb_config + Config.fb_width], eax
    mov eax, [rsp + FB_INFO_HEIGHT]
    mov [fb_config + Config.fb_height], eax
    mov eax, [rsp + FB_INFO_PITCH]
    mov [fb_config + Config.fb_stride], eax
    lea r13, [fb_config]
.start:
    lea rdi, [server]
    lea rsi, [server_arena]
    mov edx, DEFAULT_WIDTH
    mov ecx, DEFAULT_HEIGHT
    mov r8, r13
    call server_init
    test rax, rax
    js .no_server

    ; The login screen; a screen too small for it starts without one. Its
    ; calls turn the server while they wait.
    lea rdi, [server]
    lea rsi, [server_arena]
    call greeter_start

    ; The taskbar, under the login screen until it goes
    lea rdi, [server]
    lea rsi, [server_arena]
    call taskbar_start

    ; Without waitsets the loop yields instead of sleeping
    call ut_waitset_create
    mov rbx, rax

    ; The event loop: whatever woke us, one turn serves it
.loop:
    test rbx, rbx
    js .no_wait
    lea rdi, [server]                   ; awake again for a held key's repeat
    call input_repeat_deadline
    mov rdi, rbx
    mov rsi, rax                        ; 0: no deadline
    call ut_wait_wait
    jmp .serve
.no_wait:
    call ut_yield
.serve:
    lea rdi, [server]
    call server_poll
    mov rdi, [server + Server.greeter]  ; the login screen and the taskbar,
    test rdi, rdi                       ; between turns
    jz .taskbar
    call greeter_step
.taskbar:
    mov rdi, [server + Server.taskbar]
    test rdi, rdi
    jz .loop
    call taskbar_step
    jmp .loop

.no_arena:
    lea rdi, [panic_oom_msg]
    mov rsi, panic_oom_len
    jmp .panic
.no_server:
    lea rdi, [panic_server_msg]
    mov rsi, panic_server_len
.panic:
    call ut_log_write
    PANIC

section .rodata

banner_msg:     db "Canvas Display Server for Utkarsha OS", 10
banner_len:     equ $ - banner_msg

panic_oom_msg:  db "PANIC: Failed to allocate server arena", 10
panic_oom_len:  equ $ - panic_oom_msg

panic_server_msg: db "PANIC: Failed to start the server", 10
panic_server_len: equ $ - panic_server_msg

section .bss

alignb 16
server:         resb Server_size
server_arena:   resb Arena_size
fb_config:      resb Config_size

section .data

global canvasd_version
canvasd_version: dq 0x00010100   ; 0.1.1
