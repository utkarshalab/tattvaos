; ============================================================================
; RFB Input — Client-to-Server Input Forwarding (pointer/keyboard)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

section .text

%define RFB_MSG_POINTER_EVENT  5
%define RFB_MSG_KEY_EVENT      4
%define RFB_MSG_CUT_TEXT       6

; ---------------------------------------------------------------------------
; rfb_poll_input
;   Read and dispatch pending client messages (non-blocking single pass)
;   IN: rdi = RfbClient*
; ---------------------------------------------------------------------------
global rfb_poll_input
rfb_poll_input:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    ASSERT_PTR rbx
    mov r12, [rbx + RfbClient.conn]
    sub rsp, 16
    ; poll: try 1-byte read with zero timeout? tv_tls_read blocks;
    ; caller only invokes when waitset signals readability
    mov rdi, r12
    mov rsi, rsp
    mov rdx, 1
    call tv_tls_read
    cmp rax, 1
    jne .none
    movzx eax, byte [rsp]
    cmp al, RFB_MSG_POINTER_EVENT
    je .pointer
    cmp al, RFB_MSG_KEY_EVENT
    je .key
    cmp al, RFB_MSG_CUT_TEXT
    je .cut
    jmp .done
.pointer:
    mov rdi, r12
    mov rsi, rsp
    mov rdx, 5
    call rfb_tls_read_all
    test rax, rax
    jnz .done
    ; button mask, x BE, y BE
    movzx ecx, byte [rsp + 0]
    movzx edx, word [rsp + 1]
    xchg dl, dh
    movzx r8d, word [rsp + 3]
    xchg r8b, r8b  ; note: 16-bit swap via xchg below
    movzx r8d, word [rsp + 3]
    xchg r8b, al
    mov rdi, rbx
    mov rsi, rdx
    mov rdx, r8
    mov rcx, rcx
    call rfb_forward_pointer
    jmp .done
.key:
    mov rdi, r12
    mov rsi, rsp
    mov rdx, 7
    call rfb_tls_read_all
    test rax, rax
    jnz .done
    movzx ecx, byte [rsp + 0]  ; down flag
    mov edx, [rsp + 4]         ; keysym BE
    bswap edx
    mov rdi, rbx
    mov rsi, rdx
    mov rdx, rcx
    call rfb_forward_key
    jmp .done
.cut:
    ; clipboard text from client -> server clipboard
    mov rdi, rbx
    call rfb_recv_cut_text
.done:
    add rsp, 16
    xor rax, rax
    ret
.none:
    add rsp, 16
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; rfb_forward_pointer — inject into virtual seat
; ---------------------------------------------------------------------------
global rfb_forward_pointer
rfb_forward_pointer:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    ASSERT_PTR rbx
    ; rsi = x, rdx = y, rcx = buttons
    mov rdi, [rbx + RfbClient.server]
    mov rdi, [rdi + RfbServer.server]
    mov r8, -1  ; remote device id
    call virtual_input_inject
    ret

; ---------------------------------------------------------------------------
; rfb_forward_key
; ---------------------------------------------------------------------------
global rfb_forward_key
rfb_forward_key:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx
    ; TODO: keysym -> keycode map, then virtual_input_inject
    xor rax, rax
    ret

section .data
global rfb_input_version
rfb_input_version: dq 0x010000
