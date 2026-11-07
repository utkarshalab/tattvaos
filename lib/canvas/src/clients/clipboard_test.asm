; ============================================================================
; clipboard_test — Offer, Paste, Answer, Compare
; ============================================================================
; The whole round trip against itself: it offers text/plain on the
; clipboard, pastes it, answers the send that asks it for the data, and
; compares the data that comes back. The server lets only the client with
; the keyboard offer or paste, so it passes only while it has it (a window of
; its own focused, or a trusted connection).

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/canvas_client.inc"
%include "inc/client_api.inc"

extern canvas_clipboard_offer
extern canvas_clipboard_receive
extern canvas_clipboard_send
extern canvas_event_poll

%define TURNS       100000              ; polls before it gives up

section .text

global client_main
client_main:
    PROLOGUE_SAVE rbx, r12, r13
    sub rsp, 152                        ; an event (148 bytes); aligned
    mov rdi, CLIENT_CAP_DISPLAY | CLIENT_CAP_CLIPBOARD
    call canvas_connect
    test rax, rax
    jz .fail
    mov rbx, rax
    mov rdi, rbx                        ; offer
    xor esi, esi
    mov edx, 1
    lea rcx, [rel types]
    call canvas_clipboard_offer
    test rax, rax
    js .fail2
    mov rdi, rbx                        ; paste
    xor esi, esi
    lea rdx, [rel types]
    call canvas_clipboard_receive
    test rax, rax
    js .fail2
    mov r12d, eax                       ; its serial
    mov r13d, TURNS
.event:
    dec r13d
    jz .fail2
    mov rdi, rbx
    mov rsi, rsp
    call canvas_event_poll
    test eax, eax
    jz .wait
    mov eax, [rsp + ClientEvent.type]
    cmp eax, CANVAS_EV_CLIPBOARD_SEND
    je .send
    cmp eax, CANVAS_EV_CLIPBOARD_DATA
    je .data
    cmp eax, CANVAS_EV_CLIPBOARD_CANCELLED
    je .fail2
    jmp .event
.wait:
    call ut_yield
    jmp .event
.send:                                  ; asked for it: answer
    mov rdi, rbx
    mov esi, [rsp + ClientEvent.data]
    lea rdx, [rel clip_text]
    mov ecx, clip_text_len
    call canvas_clipboard_send
    jmp .event
.data:                                  ; (serial, done, length, bytes)
    cmp [rsp + ClientEvent.data], r12d
    jne .event
    cmp dword [rsp + ClientEvent.data + 8], clip_text_len
    jne .fail2
    lea rdi, [rsp + ClientEvent.data + 12]
    lea rsi, [rel clip_text]
    mov ecx, clip_text_len
    repe cmpsb
    jne .fail2
    mov rdi, clip_ok
    mov rsi, clip_ok_len
    call ut_log_write
    mov rdi, rbx
    call canvas_disconnect
    xor eax, eax
    call ut_task_exit
.fail2:
    mov rdi, clip_fail
    mov rsi, clip_fail_len
    call ut_log_write
.fail:
    mov rax, 1
    call ut_task_exit

section .rodata
types:          db "text/plain"         ; one type, 32 bytes
                times 32 - ($ - types) db 0
clip_text:      db "hello canvas clipboard"
clip_text_len:  equ $ - clip_text
clip_ok:        db "clipboard_test: PASS", 10, 0
clip_ok_len:    equ $ - clip_ok
clip_fail:      db "clipboard_test: FAIL", 10, 0
clip_fail_len:  equ $ - clip_fail

section .data
global clipboard_test_version
clipboard_test_version: dq 0x020000
