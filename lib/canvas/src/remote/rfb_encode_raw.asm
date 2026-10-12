; ============================================================================
; RFB Raw Encoding — Rect Header + Raw Tile Send
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

section .text

%define RFB_ENC_RAW    0

global rfb_send_rect_header
rfb_send_rect_header:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    sub rsp, 16
    mov ax, si
    xchg al, ah
    mov [rsp + 0], ax
    mov ax, dx
    xchg al, ah
    mov [rsp + 2], ax
    mov ax, cx
    xchg al, ah
    mov [rsp + 4], ax
    mov ax, r8w
    xchg al, ah
    mov [rsp + 6], ax
    mov eax, r9d
    bswap eax
    mov [rsp + 8], eax
    mov rdi, rbx
    mov rsi, rsp
    mov rdx, 12
    call rfb_tls_write_all
    add rsp, 16
    ret

global rfb_encode_raw_tile
rfb_encode_raw_tile:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call rfb_tls_write_all
    ret

section .data
global rfb_encode_raw_version
rfb_encode_raw_version: dq 0x010000
