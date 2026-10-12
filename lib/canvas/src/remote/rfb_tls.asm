; ============================================================================
; RFB TLS — TLS Record Helpers over tv_tls
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

section .text

global rfb_tls_write_all
rfb_tls_write_all:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    test r13, r13
    jz .done
.loop:
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call tv_tls_write
    test rax, rax
    js .fail
    test rax, rax
    jz .fail
    add r12, rax
    sub r13, rax
    jnz .loop
.done:
    xor rax, rax
    ret
.fail:
    RETURN_ERROR ECONNRESET

global rfb_tls_read_all
rfb_tls_read_all:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    test r13, r13
    jz .done
.loop:
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call tv_tls_read
    test rax, rax
    js .fail
    test rax, rax
    jz .fail
    add r12, rax
    sub r13, rax
    jnz .loop
.done:
    xor rax, rax
    ret
.fail:
    RETURN_ERROR ECONNRESET

section .data
global rfb_tls_version
rfb_tls_version: dq 0x010000
