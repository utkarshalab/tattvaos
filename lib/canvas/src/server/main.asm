; ============================================================================
; Canvas Server Entry Point — main.asm
; Called by Utkarsha loader as canvasd_init
; ============================================================================
; Startup and requests are in server_core.asm. Accepting clients on a real
; channel waits for the kernel's channels and handle passing (KRN-03, KRN-04).

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/backend.inc"
%include "inc/struct_offsets.inc"
%include "../../boot/boot_info.inc"

default rel

extern arena_init
extern server_init
extern server_poll

%define SERVER_ARENA_BYTES  (16 * 1024 * 1024)
%define DEFAULT_WIDTH       1280
%define DEFAULT_HEIGHT      800

section .text

; ---------------------------------------------------------------------------
; canvasd_init
;   Main entry point for Canvas display server
;   Called by Utkarsha loader after kernel init
;   IN:  rdi = boot_info pointer (Utkarsha boot info struct)
;   OUT: rax = negative error (never returns on success)
; ---------------------------------------------------------------------------
global canvasd_init
canvasd_init:
    PROLOGUE_SAVE rbx, r12, r13
    sub rsp, 32 + 8                     ; the capability token key
    mov r12, rdi                        ; boot info

    ; Logging first, for early debug output
    mov rdi, LOG_DEBUG
    call ut_log_set_level
    lea rdi, [banner_msg]
    mov rsi, banner_len
    call ut_log_write

    ; Entropy for capability tokens
    mov rdi, rsp
    call ut_entropy_siphash_key

    ; The server's arena
    mov edi, SERVER_ARENA_BYTES
    mov rsi, MEM_DMA
    call ut_mem_alloc
    test rax, rax
    js .no_arena
    lea rdi, [server_arena]
    mov rsi, rax
    mov edx, SERVER_ARENA_BYTES
    call arena_init

    ; The firmware's framebuffer if the loader passed one, else headless
    xor r13d, r13d
    test r12, r12
    jz .start
    mov rdi, [r12 + BOOT_INFO_FB_ADDR_OFF]
    test rdi, rdi
    jz .start
    mov esi, [r12 + BOOT_INFO_FB_PITCH_OFF]
    mov eax, [r12 + BOOT_INFO_FB_HEIGHT_OFF]
    imul rsi, rax
    mov [fb_config + Config.fb_size], rsi
    mov edx, MMIO_WC
    call ut_mmio_map
    test rax, rax
    js .start
    mov [fb_config + Config.fb_base], rax
    mov eax, [r12 + BOOT_INFO_FB_WIDTH_OFF]
    mov [fb_config + Config.fb_width], eax
    mov eax, [r12 + BOOT_INFO_FB_HEIGHT_OFF]
    mov [fb_config + Config.fb_height], eax
    mov eax, [r12 + BOOT_INFO_FB_PITCH_OFF]
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

    call ut_waitset_create
    test rax, rax
    js .no_waitset
    mov rbx, rax

    ; The event loop: whatever woke us, one turn serves it
.loop:
    mov rdi, rbx
    xor esi, esi                        ; no timeout
    call ut_wait_wait
    lea rdi, [server]
    call server_poll
    jmp .loop

.no_arena:
    lea rdi, [panic_oom_msg]
    mov rsi, panic_oom_len
    jmp .panic
.no_server:
    lea rdi, [panic_server_msg]
    mov rsi, panic_server_len
    jmp .panic
.no_waitset:
    lea rdi, [panic_waitset_msg]
    mov rsi, panic_waitset_len
.panic:
    call ut_log_write
    PANIC

section .rodata

banner_msg:     db "Canvas Display Server for Utkarsha OS", 10, 0
banner_len:     equ $ - banner_msg

panic_oom_msg:  db "PANIC: Failed to allocate server arena", 10, 0
panic_oom_len:  equ $ - panic_oom_msg

panic_server_msg: db "PANIC: Failed to start the server", 10, 0
panic_server_len: equ $ - panic_server_msg

panic_waitset_msg: db "PANIC: Failed to create main waitset", 10, 0
panic_waitset_len: equ $ - panic_waitset_msg

section .bss

alignb 16
server:         resb Server_size
server_arena:   resb Arena_size
fb_config:      resb Config_size

section .data

global canvasd_version
canvasd_version: dq 0x00010100   ; 0.1.1
