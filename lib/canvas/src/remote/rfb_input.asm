; ============================================================================
; RFB Input — Client-to-Server Input Forwarding (pointer/keyboard)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/struct_offsets.inc"
%include "inc/externs.inc"
%include "inc/event.inc"
extern rfb_recv_cut_text
extern virtual_input_inject

; struct offsets (hoisted above use)
%define RFB_MSG_POINTER_EVENT  5
%define RFB_MSG_KEY_EVENT      4
%define RFB_MSG_CUT_TEXT       6

section .text


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
    mov r12, [rbx + RfbClient_conn]
    sub rsp, 16
    ; poll: try 1-byte read with zero timeout? ut_tls_read blocks;
    ; caller only invokes when waitset signals readability
    mov rdi, r12
    mov rsi, rsp
    mov rdx, 1
    call ut_tls_read
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
    rol r8w, 8
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
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.none:
    add rsp, 16
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
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
    mov rdi, [rbx + RfbClient_server]
    mov rdi, [rdi + RfbServer_server]
    mov r8, -1  ; remote device id
    call virtual_input_inject
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; rfb_forward_key
; ---------------------------------------------------------------------------
global rfb_forward_key
rfb_forward_key:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rdx
    ASSERT_PTR rbx
    ; Translate the stable X11 keysym subset used by RFB into native evdev
    ; keycodes. Printable letters/digits are table-driven; navigation keys
    ; use their standard 0xffxx keysyms.
    mov eax, esi
    cmp eax, 'A'
    jb .digit
    cmp eax, 'Z'
    jbe .upper
    cmp eax, 'a'
    jb .special
    cmp eax, 'z'
    ja .special
    sub eax, 'a'
    movzx edx, byte [rel rfb_letter_codes + rax]
    jmp .inject
.upper:
    sub eax, 'A'
    movzx edx, byte [rel rfb_letter_codes + rax]
    jmp .inject
.digit:
    cmp eax, '0'
    jb .special
    cmp eax, '9'
    ja .special
    sub eax, '0'
    movzx edx, byte [rel rfb_digit_codes + rax]
    jmp .inject
.special:
    mov edx, 28                 ; Return
    cmp eax, 0xff0d
    je .inject
    mov edx, 1                  ; Escape
    cmp eax, 0xff1b
    je .inject
    mov edx, 14                 ; Backspace
    cmp eax, 0xff08
    je .inject
    mov edx, 15                 ; Tab
    cmp eax, 0xff09
    je .inject
    mov edx, 57                 ; Space
    cmp eax, 0x20
    je .inject
    mov edx, 103                ; Up
    cmp eax, 0xff52
    je .inject
    mov edx, 108                ; Down
    cmp eax, 0xff54
    je .inject
    mov edx, 105                ; Left
    cmp eax, 0xff51
    je .inject
    mov edx, 106                ; Right
    cmp eax, 0xff53
    jne .unsupported
.inject:
    mov rdi, [rbx + RfbClient_server]
    mov rdi, [rdi + RfbServer_server]
    mov rsi, INPUT_EVENT_KEY
    mov rcx, r12
    mov r8, -1
    call virtual_input_inject
    EPILOGUE_RESTORE rbx, r12
    ret
.unsupported:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12
    ret

section .rodata
rfb_letter_codes: db 30,48,46,32,18,33,34,35,23,36,37,38,50,49,24,25,16,19,31,20,22,47,17,45,21,44
rfb_digit_codes:  db 11,2,3,4,5,6,7,8,9,10

section .data
global rfb_input_version
rfb_input_version: dq 0x010000
