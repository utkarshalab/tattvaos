; ============================================================================
; RFB Zlib Encoding — Compressed Tile Send + Client Update Loop
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/struct_offsets.inc"

extern deflate_compress
extern rfb_tls_write_all
extern virtual_output_damage

; struct offsets (hoisted above use)
%define RFB_ENC_ZLIB   6

section .text


global rfb_encode_zlib_tile
rfb_encode_zlib_tile:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r14
    mov rdi, 0
    mov rsi, r12
    mov rdx, r13
    mov rcx, r14
    mov r8, r15
    mov r9, 1
    call deflate_compress
    test rax, rax
    js .fail
    mov r13, rax
    sub rsp, 8
    mov eax, r13d
    bswap eax
    mov [rsp + 0], eax
    mov rdi, rbx
    mov rsi, rsp
    mov rdx, 4
    call rfb_tls_write_all
    test rax, rax
    jnz .fail2
    mov rdi, rbx
    mov rsi, r14
    mov rdx, r13
    call rfb_tls_write_all
    add rsp, 8
    mov rax, r13
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.fail2:
    add rsp, 8
.fail:
    mov rax, -(ECONNRESET)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

global rfb_client_update
rfb_client_update:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    ASSERT_PTR rbx
    mov r12, [rbx + RfbClient_conn]
    mov r13, [rbx + RfbClient_server]
    mov r13, [r13 + RfbServer_voutput]
    test r13, r13
    jz .done
    mov rdi, r13
    call virtual_output_damage
    test rax, rax
    jz .done
    mov r14, rax
    sub rsp, 64
    mov byte [rsp + 0], 0
    mov byte [rsp + 1], 0
    mov eax, r14d
    xchg al, ah
    rol eax, 16
    xchg al, ah
    mov [rsp + 2], ax
    mov rdi, r12
    mov rsi, rsp
    mov rdx, 4
    call rfb_tls_write_all
    add rsp, 64
.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

section .data
global rfb_encode_zlib_version
rfb_encode_zlib_version: dq 0x010000
