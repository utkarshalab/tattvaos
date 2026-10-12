; ============================================================================
; Client Conn — Connection Setup (channel pair + handshake)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/canvas_client.inc"

section .text

struc ClientConn {
    .server_chan:    resq 1
    .tx_ring:        resq 1
    .rx_ring:        resq 1
    .handle_tx:      resq 1
    .handle_rx:      resq 1
    .caps_wanted:    resq 1
    .caps_granted:   resq 1
    .next_obj:       resd 1
    .arena:          resq 1
}
%define ClientConn_size    64

; ---------------------------------------------------------------------------
; canvas_connect
;   IN: rdi = caps_wanted u64 — OUT: rax = conn* (0 on fail)
; ---------------------------------------------------------------------------
global canvas_connect
canvas_connect:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    ; alloc conn (static arena: use tv_mem 64K)
    mov rdi, 65536
    mov rsi, 0
    call tv_mem_alloc
    test rax, rax
    js .fail
    mov r12, rax
    mov qword [r12 + ClientConn.server_chan], 0
    mov qword [r12 + ClientConn.caps_wanted], rbx
    mov qword [r12 + ClientConn.caps_granted], 0
    mov dword [r12 + ClientConn.next_obj], 1
    mov qword [r12 + ClientConn.arena], r12
    ; TODO: open channel to canvasd via Tattva service registry,
    ; send cw_display.get_caps, await grant
    mov qword [r12 + ClientConn.caps_granted], rbx
    mov rax, r12
    ret
.fail:
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; canvas_disconnect
; ---------------------------------------------------------------------------
global canvas_disconnect
canvas_disconnect:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx
    ; TODO: send disconnect, close channel
    ; free arena region
    mov rdi, [rbx + ClientConn.arena]
    ; NOTE: region handle tracked separately in real impl
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; canvas_get_caps
; ---------------------------------------------------------------------------
global canvas_get_caps
canvas_get_caps:
    PROLOGUE
    ASSERT_PTR rdi
    mov rax, [rdi + ClientConn.caps_granted]
    ret

section .data
global canvas_conn_version
canvas_conn_version: dq 0x010000
