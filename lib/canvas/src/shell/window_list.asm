; ============================================================================
; Window List — Every Window, for Taskbars (proto/canvas-shell.cwp)
; ============================================================================
; A client with the windows capability subscribes and is sent a window event
; for every toplevel there is, then which one has the keyboard; from then on
; it is told of each window that appears or changes (title, app id, states),
; each that goes, and each change of the keyboard. Windows are named by
; Window.number, the same for every client. Up to WINDOW_LIST_MAX clients
; subscribe at once; one that disconnects is forgotten.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/cwp.inc"
%include "inc/cwp_ops.inc"
%include "inc/channel.inc"
%include "inc/backend.inc"
%include "inc/struct_offsets.inc"

extern msgbuf_write

%define WINDOW_EVENT_BYTES  136         ; id, states, title[64], app_id[64]

section .text

; ---------------------------------------------------------------------------
; window_list_subscribe
;   IN:  rdi = server*, rsi = client*
;   OUT: rax = 0, -ENOSPC with WINDOW_LIST_MAX watching already
; ---------------------------------------------------------------------------
global window_list_subscribe
window_list_subscribe:
    PROLOGUE_SAVE rbx, r12, r13
    sub rsp, 8                          ; 16-byte aligned
    mov rbx, rdi
    mov r12, rsi
    xor ecx, ecx                        ; its slot, or the first free one
    mov rdx, -1
.slot:
    mov rax, [rbx + Server.window_lists + rcx * 8]
    cmp rax, r12
    je .listed                          ; once is enough
    test rax, rax
    jnz .next_slot
    cmp rdx, -1
    jne .next_slot
    mov rdx, rcx
.next_slot:
    inc ecx
    cmp ecx, WINDOW_LIST_MAX
    jb .slot
    mov rax, -(ENOSPC)
    cmp rdx, -1
    je .out
    mov [rbx + Server.window_lists + rdx * 8], r12
.listed:
    ; Everything there is, to it alone
    mov r13, [rbx + Server.windows]
.window:
    test r13, r13
    jz .active
    mov rdi, r13
    mov rsi, r12
    call send_window
    mov r13, [r13 + Window.next]
    jmp .window
.active:
    mov edi, [rbx + Server.window_active]
    mov rsi, r12
    call send_number_activated
    xor eax, eax
.out:
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13

; ---------------------------------------------------------------------------
; window_list_forget
;   A client going stops being told
;   IN:  rdi = server*, rsi = client*
; ---------------------------------------------------------------------------
global window_list_forget
window_list_forget:
    xor ecx, ecx
.slot:
    cmp [rdi + Server.window_lists + rcx * 8], rsi
    jne .next
    mov qword [rdi + Server.window_lists + rcx * 8], 0
.next:
    inc ecx
    cmp ecx, WINDOW_LIST_MAX
    jb .slot
    xor eax, eax
    ret

; ---------------------------------------------------------------------------
; window_list_changed
;   A toplevel appeared or changed: every subscriber is sent its window event
;   IN:  rdi = server*, rsi = Window*
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global window_list_changed
window_list_changed:
    mov rdi, rsi
    xor esi, esi
    jmp send_window

; ---------------------------------------------------------------------------
; window_list_removed
;   A toplevel went
;   IN:  rdi = server*, rsi = Window*
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global window_list_removed
window_list_removed:
    mov esi, [rsi + Window.number]
    mov edx, WINDOW_LIST_EVENT_REMOVED
    jmp broadcast_number

; ---------------------------------------------------------------------------
; window_list_activated
;   The keyboard moved; subscribers hear if the window that has it changed
;   IN:  rdi = server*, rsi = surface* with the keyboard, 0 for none
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global window_list_activated
window_list_activated:
    xor eax, eax                        ; its window's number, 0 if none
    test rsi, rsi
    jz .have
    mov rcx, [rsi + Surface.window]
    test rcx, rcx
    jz .have
    cmp dword [rcx + Window.kind], ROLE_TOPLEVEL
    jne .have
    mov eax, [rcx + Window.number]
.have:
    cmp eax, [rdi + Server.window_active]
    je .same
    mov [rdi + Server.window_active], rax
    mov esi, eax
    mov edx, WINDOW_LIST_EVENT_ACTIVATED
    jmp broadcast_number
.same:
    xor eax, eax
    ret

; ---------------------------------------------------------------------------
; window_list_find
;   IN:  rdi = server*, esi = a window's number
;   OUT: rax = its surface*, 0 if there is none
; ---------------------------------------------------------------------------
global window_list_find
window_list_find:
    mov rax, [rdi + Server.windows]
.next:
    test rax, rax
    jz .none
    cmp [rax + Window.number], esi
    je .found
    mov rax, [rax + Window.next]
    jmp .next
.found:
    mov rax, [rax + Window.surface]
    ret
.none:
    xor eax, eax
    ret

; ---------------------------------------------------------------------------
; Local
; ---------------------------------------------------------------------------

; window(id, states, title, app_id) to one client, or every subscriber.
; rdi = Window*, rsi = client*, 0 for every subscriber -> rax = 0
send_window:
    PROLOGUE_SAVE rbx, r12
    sub rsp, 16 + WINDOW_EVENT_BYTES + 8    ; header, payload; 16-byte aligned
    mov rbx, rdi
    mov r12, rsi
    mov eax, [rbx + Window.number]
    mov [rsp + 16], eax
    mov eax, [rbx + Window.state]
    mov [rsp + 20], eax
    lea rdi, [rsp + 24]
    lea rsi, [rbx + Window.title]
    mov ecx, 64
    rep movsb
    lea rdi, [rsp + 88]
    lea rsi, [rbx + Window.app_id]
    mov ecx, 64
    rep movsb
    mov dword [rsp + MsgHdr.obj], CWP_OBJ_WINDOW_LIST
    mov word [rsp + MsgHdr.opcode], WINDOW_LIST_EVENT_WINDOW
    mov word [rsp + MsgHdr.flags], CWP_MSG_FLAG_IS_EVENT
    mov dword [rsp + MsgHdr.len], WINDOW_EVENT_BYTES
    mov rdi, [rbx + Window.server]
    mov rsi, rsp
    lea rdx, [rsp + 16]
    mov rcx, r12
    call deliver
    add rsp, 16 + WINDOW_EVENT_BYTES + 8
    EPILOGUE_RESTORE rbx, r12

; activated(id) to one client.
; edi = id, rsi = client* -> rax = 0
send_number_activated:
    sub rsp, 40                         ; header at 0, payload at 16
    mov [rsp + 16], edi
    mov dword [rsp + MsgHdr.obj], CWP_OBJ_WINDOW_LIST
    mov word [rsp + MsgHdr.opcode], WINDOW_LIST_EVENT_ACTIVATED
    mov word [rsp + MsgHdr.flags], CWP_MSG_FLAG_IS_EVENT
    mov dword [rsp + MsgHdr.len], 4
    mov rdi, [rsi + Client.rx_ring]
    mov rsi, rsp
    lea rdx, [rsp + 16]
    call msgbuf_write
    xor eax, eax
    add rsp, 40
    ret

; An event carrying one number to every subscriber.
; rdi = server, esi = the number, edx = the event -> rax = 0
broadcast_number:
    sub rsp, 40                         ; header at 0, payload at 16
    mov [rsp + 16], esi
    mov dword [rsp + MsgHdr.obj], CWP_OBJ_WINDOW_LIST
    mov [rsp + MsgHdr.opcode], dx
    mov word [rsp + MsgHdr.flags], CWP_MSG_FLAG_IS_EVENT
    mov dword [rsp + MsgHdr.len], 4
    mov rsi, rsp
    lea rdx, [rsp + 16]
    xor ecx, ecx
    call deliver
    add rsp, 40
    ret

; A message to one client, or to every subscriber.
; rdi = server, rsi = header, rdx = payload, rcx = client*, 0: every one
deliver:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    test rcx, rcx
    jz .all
    mov rdi, [rcx + Client.rx_ring]
    call msgbuf_write
    jmp .done
.all:
    xor r14d, r14d
.slot:
    mov rax, [rbx + Server.window_lists + r14 * 8]
    test rax, rax
    jz .next
    mov rdi, [rax + Client.rx_ring]
    mov rsi, r12
    mov rdx, r13
    call msgbuf_write
.next:
    inc r14d
    cmp r14d, WINDOW_LIST_MAX
    jb .slot
.done:
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12, r13, r14
