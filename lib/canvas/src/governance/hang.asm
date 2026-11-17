; ============================================================================
; Hang — "Not Responding" and Force Quit
; ============================================================================
; REL-14. When the user presses a key or button and the window with the
; keyboard belongs to a client that has answered every ping so far, the
; client is pinged (cw_display.ping, a new serial). It answers with
; cw_display.pong; the client library does that by itself whenever it reads
; its messages. One that has not answered in HANG_NS is hung: a dialog the
; server draws (desktop/menu) says it is not responding and offers Wait
; (another HANG_NS) or Force quit (its connection closed, its windows gone).
; An answer, or the client going, takes the dialog away.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/cwp.inc"
%include "inc/cwp_ops.inc"
%include "inc/struct_offsets.inc"

extern client_get
extern menu_close
extern menu_hung_client
extern menu_open_kind
extern hung_menu_open
extern sync_event
extern ut_time_now_ns

%define HANG_NS     5000000000          ; five seconds

section .text

; ---------------------------------------------------------------------------
; hang_step
;   Once a turn: ping the client the user is pressing keys and buttons in,
;   and if it has not answered for HANG_NS, offer to force quit it
;   IN:  rdi = server*
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global hang_step
hang_step:
    PROLOGUE_SAVE rbx, r12, r13
    sub rsp, 8                          ; 16-byte aligned
    mov rbx, rdi
    call menu_hung_client               ; a dialog for one gone or answering:
    test rax, rax                       ; away
    jz .focus
    mov rdi, rbx
    mov rsi, rax
    call client_get
    test rax, rax
    jz .close
    cmp qword [rax + Client.hung], 0
    jne .focus
.close:
    mov rdi, rbx
    call menu_close
.focus:
    mov rax, [rbx + Server.input_seat]
    test rax, rax
    jz .out
    mov rcx, [rax + InputSeat.keyboard_focus]
    test rcx, rcx
    jz .out
    mov r12, [rcx + Surface.client]
    test r12, r12
    jz .out
    mov r13, [rax + InputSeat.last_input]
    cmp qword [r12 + Client.hang_since], 0
    jne .waiting
    test r13, r13                       ; a press since its last answer: ping
    jz .out
    cmp r13, [r12 + Client.hang_answered]
    jbe .out
    call ut_time_now_ns
    mov [r12 + Client.hang_since], rax
    inc qword [r12 + Client.hang_serial]
    mov rdi, r12
    mov esi, CWP_OBJ_DISPLAY
    mov edx, DISPLAY_EV_PING
    lea rcx, [r12 + Client.hang_serial]
    mov r8d, 8
    call sync_event
    jmp .out
.waiting:
    cmp qword [r12 + Client.hung], 0
    jne .out
    call ut_time_now_ns
    sub rax, [r12 + Client.hang_since]
    mov rcx, HANG_NS
    cmp rax, rcx
    jb .out
    mov qword [r12 + Client.hung], 1    ; not responding
    call menu_open_kind
    test eax, eax
    jnz .out                            ; another menu up: offered later
    mov rdi, rbx
    mov rsi, [r12 + Client.id]
    call hung_menu_open
.out:
    xor eax, eax
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13

; ---------------------------------------------------------------------------
; hang_pong
;   A client's pong: the serial last sent answers the ping
;   IN:  rdi = server*, rsi = client*, rdx = serial
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global hang_pong
hang_pong:
    cmp qword [rsi + Client.hang_since], 0
    je .out
    cmp rdx, [rsi + Client.hang_serial]
    jne .out                            ; an old one
    push rsi                            ; 16-byte aligned
    call ut_time_now_ns
    pop rsi
    mov [rsi + Client.hang_answered], rax
    mov qword [rsi + Client.hang_since], 0
    mov qword [rsi + Client.hung], 0
.out:
    xor eax, eax
    ret

; ---------------------------------------------------------------------------
; hang_wait
;   The user chose Wait: another HANG_NS from now
;   IN:  rdi = client*
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global hang_wait
hang_wait:
    push rdi                            ; 16-byte aligned
    call ut_time_now_ns
    pop rdi
    mov [rdi + Client.hang_since], rax
    mov qword [rdi + Client.hung], 0
    xor eax, eax
    ret

section .data
global hang_version
hang_version: dq 0x010000
