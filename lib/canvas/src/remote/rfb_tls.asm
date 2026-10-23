; ============================================================================
; RFB TLS — TLS Record Helpers over ut_tls
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"

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
    call ut_tls_write
    test rax, rax
    js .fail
    test rax, rax
    jz .fail
    add r12, rax
    sub r13, rax
    jnz .loop
.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.fail:
    mov rax, -(ECONNRESET)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

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
    call ut_tls_read
    test rax, rax
    js .fail
    test rax, rax
    jz .fail
    add r12, rax
    sub r13, rax
    jnz .loop
.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.fail:
    mov rax, -(ECONNRESET)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

section .data
global rfb_tls_version
rfb_tls_version: dq 0x010000
