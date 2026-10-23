; =============================================================================
; File     : apps/ish/src/main.asm
; Project  : Utkarsha OS — Ishana Shell
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Shell entry point — context init, REPL loop, shutdown.
; =============================================================================

%ifndef ISH_MAIN_ASM
%define ISH_MAIN_ASM

%include "inc/ish.inc"
%include "inc/frontend.inc"
%include "inc/cmd_registry.inc"
%include "inc/env.inc"
%include "inc/errors.inc"

%include "lib/str/str.asm"
%include "lib/io/io.asm"

bits 64

section .bss
align 16
ish_ctx:      resb ISH_CTX_SIZE

section .data
align 16
ish_default_prompt:   db "ut> ", 0
ISH_DEFAULT_PROMPT_LEN equ $ - ish_default_prompt - 1   ; without the NUL
ish_welcome_banner:   db "Utkarsha OS — Ishana Shell v1.0.0", 0x0A
                      db "Type 'help' for available commands.", 0x0A, 0
ish_goodbye_msg:      db "logout", 0x0A, 0

section .text

; -----------------------------------------------------------------------------
; ish_main — Shell entry point
; Input:  rdi = frontend ptr, rsi = flags (ISH_FLAG_*)
; Output: rax = exit code (never returns normally)
; -----------------------------------------------------------------------------
global ish_main
ish_main:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15

    mov     r12, rdi                      ; r12 = frontend ptr
    mov     r13, rsi                      ; r13 = flags

    ; ---- Zero-init context ----
    mov     rdi, ish_ctx
    mov     rcx, ISH_CTX_SIZE / 8
    xor     rax, rax
    cld
    rep     stosq

    mov     rdi, ish_ctx
    mov     eax, 0x49534821               ; "ISH!" magic
    mov     [rdi + ish_ctx.magic], eax
    mov     eax, 0x00010000               ; version 1.0
    mov     [rdi + ish_ctx.version], eax
    mov     eax, r13d
    mov     [rdi + ish_ctx.flags], eax
    mov     [rdi + ish_ctx.frontend], r12

    ; Default prompt
    mov     qword [rdi + ish_ctx.prompt], ish_default_prompt
    mov     eax, ISH_DEFAULT_PROMPT_LEN   ; "ut> " length
    mov     [rdi + ish_ctx.prompt_len], eax

    ; ---- Initialize subsystems ----
    mov     rdi, r12                      ; frontend ptr
    call    frontend_init

    call    env_init
    call    cmd_registry_init
    call    config_load
    call    history_init

    ; ---- Print welcome banner ----
    mov     rdi, ish_welcome_banner
    call    frontend_write_str

    ; ---- Main REPL Loop ----
.loop:
    cmp     dword [ish_ctx + ish_ctx.running], 0
    jz      .shutdown

    ; Check pending interrupt
    cmp     dword [ish_ctx + ish_ctx.interrupt_pending], 0
    jnz     .handle_interrupt

    ; Set prompt
    mov     rdi, [ish_ctx + ish_ctx.prompt]
    test    rdi, rdi
    jz      .use_default_prompt
    call    frontend_set_prompt
    jmp .read_input

.use_default_prompt:
    mov     rdi, ish_default_prompt
    call    frontend_set_prompt

.read_input:
    mov     rdi, .line_buf
    mov     rsi, ISH_MAX_LINE_LEN
    call    frontend_read_line            ; rax = bytes read or -1
    cmp     rax, -1
    je      .eof                          ; EOF (Ctrl-D)

    test    rax, rax
    jz      .loop                         ; Empty line, reprompt

    ; Tokenize input line
    mov     rdi, .line_buf
    call    parser_tokenize               ; fills argc/argv
    cmp     eax, -1
    je      .loop                         ; Tokenizer error

    ; Expand variables / aliases
    call    parser_expand

    ; Dispatch command
    mov     rdi, [.argc]
    mov     rsi, .argv_area
    call    exec_dispatch                 ; rax = exit code
    mov     [ish_ctx + ish_ctx.exit_code], eax

    jmp .loop

.handle_interrupt:
    mov     dword [ish_ctx + ish_ctx.interrupt_pending], 0
    mov     rdi, msg_interrupt
    call    frontend_write_str
    jmp .loop

.eof:
    mov     rdi, ish_goodbye_msg
    call    frontend_write_str

.shutdown:
    call    history_save
    call    env_save
    mov     rdi, [ish_ctx + ish_ctx.frontend]
    call    frontend_shutdown

    mov     eax, [ish_ctx + ish_ctx.exit_code]
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

section .bss
align 16
.line_buf:      resb ISH_MAX_LINE_LEN
.argc:          resd 1
.argv_area:     resq ISH_MAX_ARGS * 8     ; array of char* pointers

section .rodata
align 16
msg_interrupt:  db "^C", 0x0A, 0

%endif ; ISH_MAIN_ASM