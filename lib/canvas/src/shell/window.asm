; ============================================================================
; Window — Surfaces with the Toplevel Role (proto/canvas-shell.cwp)
; ============================================================================
; A client makes a surface a window with cw_toplevel.create; the server then
; owns where it goes. The first commit that shows a buffer places it with its
; top-left at the pointer, moved back so all of it fits on the output where
; it can; from then on each commit puts it where the server keeps it and the
; x, y of attach are ignored. Raising and the keyboard on first show are
; stacking's (shell/stacking.asm), as for any surface.
;
; Every window is on Server.windows, newest first, for a task list. A Window
; lives in its client's arena: a disconnect frees it with the rest.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/cwp.inc"
%include "inc/channel.inc"
%include "inc/backend.inc"
%include "inc/struct_offsets.inc"

extern arena_alloc
extern handle_resolve
extern msgbuf_write

; cw_toplevel events
%define EV_CONFIGURE    0
%define EV_CLOSE        1

section .text

; ---------------------------------------------------------------------------
; window_create
;   Make a surface a window and send it its first configure
;   IN:  rdi = server*, rsi = surface*
;   OUT: rax = 0, -EEXIST if it is one already, -ENOMEM
; ---------------------------------------------------------------------------
global window_create
window_create:
    PROLOGUE_SAVE rbx, r12, r13
    sub rsp, 8                          ; 16-byte aligned
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov rax, -(EEXIST)
    cmp qword [r12 + Surface.window], 0
    jne .out

    mov rax, [r12 + Surface.client]
    mov rdi, [rax + Client.arena]
    mov esi, Window_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov r13, rax
    mov rdi, rax
    xor eax, eax
    mov ecx, Window_size
    rep stosb
    mov [r13 + Window.server], rbx
    mov [r13 + Window.surface], r12
    mov rax, [rbx + Server.windows]
    mov [r13 + Window.next], rax
    mov [rbx + Server.windows], r13
    mov [r12 + Surface.window], r13

    mov rdi, r12                        ; any size it likes, for now
    xor esi, esi
    xor edx, edx
    call window_configure
    xor eax, eax
.out:
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13
.oom:
    mov rax, -(ENOMEM)
    jmp .out

; ---------------------------------------------------------------------------
; window_destroy
;   The surface is no longer a window; it stays where it was put
;   IN:  rdi = server*, rsi = surface*
;   OUT: rax = 0, -EINVAL if it is not a window
; ---------------------------------------------------------------------------
global window_destroy
window_destroy:
    mov rax, [rsi + Surface.window]
    test rax, rax
    jz .invalid
    lea rcx, [rdi + Server.windows]
.find:
    mov rdx, [rcx]
    test rdx, rdx
    jz .unlinked
    cmp rdx, rax
    je .unlink
    lea rcx, [rdx + Window.next]
    jmp .find
.unlink:
    mov rdx, [rax + Window.next]
    mov [rcx], rdx
.unlinked:
    mov qword [rsi + Surface.window], 0
    xor eax, eax
    ret
.invalid:
    mov rax, -(EINVAL)
    ret

; ---------------------------------------------------------------------------
; window_set_name
;   Its title or app id
;   IN:  rdi = surface*, esi = 0 title / 1 app id, rdx = UTF-8 bytes,
;        ecx = length
;   OUT: rax = 0, -EINVAL if it is not a window or the name is longer than
;        WINDOW_NAME_MAX
; ---------------------------------------------------------------------------
global window_set_name
window_set_name:
    mov rax, [rdi + Surface.window]
    test rax, rax
    jz .invalid
    cmp ecx, WINDOW_NAME_MAX
    ja .invalid
    lea rdi, [rax + Window.title]
    lea r8, [rax + Window.title_len]
    test esi, esi
    jz .copy
    lea rdi, [rax + Window.app_id]
    lea r8, [rax + Window.app_id_len]
.copy:
    mov [r8], ecx
    mov ecx, ecx
    mov rsi, rdx
    rep movsb
    mov byte [rdi], 0
    xor eax, eax
    ret
.invalid:
    mov rax, -(EINVAL)
    ret

; ---------------------------------------------------------------------------
; window_ack_configure
;   IN:  rdi = surface*, esi = serial
;   OUT: rax = 0, -EINVAL if it is not a window or no such configure was sent
; ---------------------------------------------------------------------------
global window_ack_configure
window_ack_configure:
    mov rax, [rdi + Surface.window]
    test rax, rax
    jz .invalid
    test esi, esi
    jz .invalid
    cmp esi, [rax + Window.serial]
    ja .invalid
    mov [rax + Window.acked], esi
    xor eax, eax
    ret
.invalid:
    mov rax, -(EINVAL)
    ret

; ---------------------------------------------------------------------------
; window_configure
;   Suggest a size; the client answers with ack_configure
;   IN:  rdi = surface* (a window), esi = width, edx = height (0, 0: its own)
;   OUT: rax = the serial sent
; ---------------------------------------------------------------------------
global window_configure
window_configure:
    PROLOGUE_SAVE rbx
    sub rsp, 8                          ; 16-byte aligned
    mov rbx, [rdi + Surface.window]
    ASSERT_PTR rbx
    mov r8d, esi
    mov r9d, edx
    mov ecx, [rbx + Window.serial]
    inc ecx
    mov [rbx + Window.serial], ecx
    mov esi, EV_CONFIGURE
    mov edx, 16
    call send_event
    mov eax, [rbx + Window.serial]
    add rsp, 8
    EPILOGUE_RESTORE rbx

; ---------------------------------------------------------------------------
; window_close
;   Ask a window's client to close it
;   IN:  rdi = surface* (a window)
;   OUT: rax from the channel
; ---------------------------------------------------------------------------
global window_close
window_close:
    mov esi, EV_CLOSE
    mov edx, 4
    jmp send_event

; ---------------------------------------------------------------------------
; window_commit
;   After a commit: a window showing its first buffer is placed, and every
;   window is put where the server keeps it
;   IN:  rdi = server*, rsi = surface*
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global window_commit
window_commit:
    PROLOGUE_SAVE rbx, r12, r13
    sub rsp, 8                          ; 16-byte aligned
    mov rbx, rdi
    mov r12, rsi
    mov r13, [r12 + Surface.window]
    test r13, r13
    jz .out
    cmp dword [r13 + Window.placed], 0
    jne .put
    mov rsi, [r12 + Surface.current + SurfaceState.buffer]
    test rsi, rsi
    jz .out                             ; nothing to place yet
    mov rdi, [rbx + Server.buffer_table]
    call handle_resolve
    test rax, rax
    jz .out
    mov rdi, rbx
    mov rsi, r13
    mov edx, [rax + Buffer.width]
    mov ecx, [rax + Buffer.height]
    call place
    mov dword [r13 + Window.placed], 1
.put:
    mov eax, [r13 + Window.x]
    mov [r12 + Surface.current + SurfaceState.buf_x], eax
    mov eax, [r13 + Window.y]
    mov [r12 + Surface.current + SurfaceState.buf_y], eax
.out:
    xor eax, eax
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13

; ---------------------------------------------------------------------------
; Local
; ---------------------------------------------------------------------------

; Top-left at the pointer (the output's centre with no seat), then back
; inside the output as far as it goes; one larger than the output starts at
; its top-left.
; rdi = server, rsi = window, edx = width, ecx = height
place:
    mov r8, [rdi + Server.outputs]
    test r8, r8
    jz .done
    mov r9, [rdi + Server.input_seat]
    test r9, r9
    jz .centre
    mov eax, [r9 + InputSeat.x]
    mov r10d, [r9 + InputSeat.y]
    jmp .clamp
.centre:
    mov eax, [r8 + Output.width]
    shr eax, 1
    add eax, [r8 + Output.x]
    mov r10d, [r8 + Output.height]
    shr r10d, 1
    add r10d, [r8 + Output.y]
.clamp:
    mov r11d, [r8 + Output.x]           ; x: no further right than fits
    add r11d, [r8 + Output.width]
    sub r11d, edx
    cmp eax, r11d
    cmovg eax, r11d
    cmp eax, [r8 + Output.x]            ; and not left of the output
    cmovl eax, [r8 + Output.x]
    mov [rsi + Window.x], eax
    mov r11d, [r8 + Output.y]           ; y the same way
    add r11d, [r8 + Output.height]
    sub r11d, ecx
    cmp r10d, r11d
    cmovg r10d, r11d
    cmp r10d, [r8 + Output.y]
    cmovl r10d, [r8 + Output.y]
    mov [rsi + Window.y], r10d
.done:
    ret

; An event to the window's client: (surface, a, b, c), edx bytes of it.
; rdi = surface, esi = event, edx = length, ecx = a, r8d = b, r9d = c
send_event:
    PROLOGUE
    sub rsp, 32                         ; header at 0, payload at 16
    mov rax, [rdi + Surface.client]
    test rax, rax
    jz .out
    mov r10d, [rdi + Surface.id]
    mov [rsp + 16], r10d
    mov [rsp + 20], ecx
    mov [rsp + 24], r8d
    mov [rsp + 28], r9d
    mov dword [rsp + MsgHdr.obj], CWP_OBJ_TOPLEVEL
    mov [rsp + MsgHdr.opcode], si
    mov word [rsp + MsgHdr.flags], CWP_MSG_FLAG_IS_EVENT
    mov [rsp + MsgHdr.len], edx
    mov rdi, [rax + Client.rx_ring]
    mov rsi, rsp
    lea rdx, [rsp + 16]
    call msgbuf_write
.out:
    EPILOGUE
