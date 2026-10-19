; ============================================================================
; RFB Auth — Token Challenge/Response (no legacy VNC auth)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/struct_offsets.inc"

section .text

global rfb_auth
rfb_auth:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    ASSERT_PTR rbx
    mov r12, [rbx + RfbClient_conn]
    sub rsp, 16
    mov dword [rsp + 0], 0x01000000
    mov rdi, r12
    mov rsi, rsp
    mov rdx, 4
    call tv_tls_write
    cmp rax, 4
    jne .fail
    mov rdi, r12
    mov rsi, rsp
    mov rdx, 4
    call tv_tls_read
    cmp rax, 4
    jne .fail
    mov eax, [rsp]
    bswap eax
    mov r13d, eax
    cmp r13d, 64
    ja .fail
    test r13d, r13d
    jz .ok_none
    sub rsp, 64
    mov rdi, r12
    mov rsi, rsp
    mov rdx, r13
    call tv_tls_read
    cmp rax, r13
    jne .fail2
    add rsp, 64
.ok_none:
    mov dword [rsp + 0], 0
    mov rdi, r12
    mov rsi, rsp
    mov rdx, 4
    call tv_tls_write
    add rsp, 16
    cmp rax, 4
    jne .fail
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.fail2:
    add rsp, 64
.fail:
    add rsp, 16
    mov rax, -(EREMOTE_TLS)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

section .data
global rfb_auth_version
rfb_auth_version: dq 0x010000
