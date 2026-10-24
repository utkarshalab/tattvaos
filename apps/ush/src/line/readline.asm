; =============================================================================
; File     : apps/ush/src/line/readline.asm
; Project  : Utkarsha OS — Utkarsha Shell
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Buffered line input with editing support.
; =============================================================================

%ifndef USH_READLINE_ASM
%define USH_READLINE_ASM

%include "inc/ush.inc"
%include "inc/frontend.inc"

bits 64

section .bss
align 16
readline_buf:     resb USH_MAX_LINE_LEN
readline_pos:     resq 1
readline_len:     resq 1

section .text

; -----------------------------------------------------------------------------
; line_read — Read a line from frontend with editing
; Input:  rdi = buffer, rsi = max_len
; Output: rax = bytes read or -1 on EOF
; -----------------------------------------------------------------------------
global line_read
line_read:
    PROLOGUE_SAVE rbx, r12, r13

    mov     r12, rdi                      ; r12 = buffer
    mov     r13, rsi                      ; r13 = max_len
    mov     qword [readline_pos], 0
    mov     qword [readline_len], 0

.read_loop:
    cmp     qword [readline_len], r13
    jge     .line_full

    ; Get char from frontend
    mov     rdi, [ush_ctx + ush_ctx.frontend]
    call    frontend_get_char
    cmp     rax, -1
    je      .read_loop                    ; no char yet, poll (cooperative yield)

    cmp     rax, 0x0A                     ; newline
    je      .line_complete
    cmp     rax, 0x0D                     ; carriage return
    je      .line_complete

    cmp     rax, 0x08                     ; backspace
    je      .line_backspace
    cmp     rax, 0x7F                     ; delete
    je      .line_backspace

    cmp     rax, 0x03                     ; Ctrl-C
    je      .line_ctrl_c

    ; Echo char
    mov     rdi, [ush_ctx + ush_ctx.frontend]
    mov     rsi, rax
    call    frontend_write_char

    ; Store char
    mov     rbx, [readline_len]
    mov     [r12 + rbx], al
    inc     qword [readline_len]
    jmp .read_loop

.line_complete:
    mov     rbx, [readline_len]
    mov     byte [r12 + rbx], 0           ; null terminate
    mov     rax, [readline_len]
    jmp .read_done

.line_backspace:
    cmp     qword [readline_len], 0
    je      .read_loop
    dec     qword [readline_len]
    mov     rbx, [readline_len]
    mov     byte [r12 + rbx], 0
    ; Echo backspace
    mov     rdi, [ush_ctx + ush_ctx.frontend]
    mov     rsi, 0x08
    call    frontend_write_char
    mov     rsi, ' '
    call    frontend_write_char
    mov     rsi, 0x08
    call    frontend_write_char
    jmp .read_loop

.line_ctrl_c:
    mov     dword [ush_ctx + ush_ctx.interrupt_pending], 1
    mov     rax, -1

.line_full:
    mov     rax, -1

.read_done:
    EPILOGUE_RESTORE rbx, r12, r13
    ret

%endif ; USH_READLINE_ASM