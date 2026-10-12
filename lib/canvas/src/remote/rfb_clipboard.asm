; ============================================================================
; RFB Clipboard — ServerCutText / ClientCutText Forwarding
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

section .text

; ---------------------------------------------------------------------------
; rfb_recv_cut_text
;   IN: rdi = RfbClient* (length+text follow on wire)
; ---------------------------------------------------------------------------
global rfb_recv_cut_text
rfb_recv_cut_text:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    ASSERT_PTR rbx
    mov r12, [rbx + RfbClient.conn]
    sub rsp, 16
    ; 3 bytes padding + u32 length BE
    mov rdi, r12
    mov rsi, rsp
    mov rdx, 7
    call rfb_tls_read_all
    test rax, rax
    jnz .fail
    mov eax, [rsp + 3]
    bswap eax
    mov r13d, eax
    cmp r13d, 1024 * 1024
    ja .fail
    test r13d, r13d
    jz .done
    ; alloc + read text
    mov rax, [rbx + RfbClient.server]
    mov rax, [rax + RfbServer.server]
    mov rdi, [rax + Server.arena]
    mov rsi, r13
    call arena_alloc
    test rax, rax
    jz .fail
    mov r14, rax
    mov rdi, r12
    mov rsi, r14
    mov rdx, r13
    call rfb_tls_read_all
    test rax, rax
    jnz .fail
    ; set server clipboard text/plain
    mov rax, [rbx + RfbClient.server]
    mov rax, [rax + RfbServer.server]
    mov rdi, rax
    mov rsi, 0  ; source client: remote
    mov rdx, mime_text_plain
    mov rcx, 10
    mov r8, r14
    mov r9, r13
    call clipboard_set
.done:
    add rsp, 16
    xor rax, rax
    ret
.fail:
    add rsp, 16
    RETURN_ERROR ECONNRESET

; ---------------------------------------------------------------------------
; rfb_send_cut_text
;   IN: rdi = RfbClient*, rsi = text, rdx = len
; ---------------------------------------------------------------------------
global rfb_send_cut_text
rfb_send_cut_text:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov r14, [rbx + RfbClient.conn]
    sub rsp, 16
    mov byte [rsp + 0], 3  ; ServerCutText
    mov byte [rsp + 1], 0
    mov byte [rsp + 2], 0
    mov byte [rsp + 3], 0
    mov eax, r13d
    bswap eax
    mov [rsp + 4], eax
    mov rdi, r14
    mov rsi, rsp
    mov rdx, 8
    call rfb_tls_write_all
    test rax, rax
    jnz .fail
    mov rdi, r14
    mov rsi, r12
    mov rdx, r13
    call rfb_tls_write_all
    add rsp, 16
    ret
.fail:
    add rsp, 16
    RETURN_ERROR ECONNRESET

section .rodata
mime_text_plain: db "text/plain", 0

section .data
global rfb_clipboard_version
rfb_clipboard_version: dq 0x010000
