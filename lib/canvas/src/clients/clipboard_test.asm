; ============================================================================
; clipboard_test — Set + Get Clipboard Round-Trip
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/canvas_client.inc"

section .text

global client_main
client_main:
    PROLOGUE_SAVE rbx
    mov rdi, CLIENT_CAP_DISPLAY | CLIENT_CAP_DATA
    call canvas_connect
    test rax, rax
    jz .fail
    mov rbx, rax
    ; set
    mov rdi, rbx
    mov rsi, mime_plain
    mov rdx, 10
    mov rcx, clip_text
    mov r8, clip_text_len
    call canvas_clipboard_set
    test rax, rax
    jnz .fail2
    ; get
    mov rdi, rbx
    mov rsi, mime_plain
    call canvas_clipboard_get
    test rax, rax
    jz .fail2
    ; compare
    mov rdi, rax
    mov rsi, clip_text
    mov rdx, clip_text_len
    call memcmp_client
    test rax, rax
    jnz .fail2
    mov rdi, clip_ok
    mov rsi, clip_ok_len
    call tv_log_write
    mov rdi, rbx
    call canvas_disconnect
    xor rax, rax
    call tv_task_exit
.fail2:
    mov rdi, clip_fail
    mov rsi, clip_fail_len
    call tv_log_write
.fail:
    mov rax, 1
    call tv_task_exit

memcmp_client:
    PROLOGUE_SAVE rbx, rcx
    mov rbx, rdi
    xor rax, rax
.loop:
    test rdx, rdx
    jz .done
    mov cl, [rbx]
    cmp cl, [rsi]
    jne .diff
    inc rbx
    inc rsi
    dec rdx
    jmp .loop
.diff:
    mov rax, 1
.done:
    EPILOGUE_RESTORE rbx, rcx
    ret

section .rodata
mime_plain: db "text/plain", 0
clip_text: db "hello canvas clipboard", 0
clip_text_len: equ $ - clip_text
clip_ok: db "clipboard_test: PASS", 10, 0
clip_ok_len: equ $ - clip_ok
clip_fail: db "clipboard_test: FAIL", 10, 0
clip_fail_len: equ $ - clip_fail

section .data
global clipboard_test_version
clipboard_test_version: dq 0x010000
