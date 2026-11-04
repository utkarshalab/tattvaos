; ============================================================================
; Window — Shell Roles: Toplevels, Popups, Layers (proto/canvas-shell.cwp)
; ============================================================================
; A client gives a surface a role; the server then owns where it goes, and
; the x, y of attach are ignored. Each commit puts the surface where its role
; says:
;
;   toplevel  placed the first time it shows a buffer, its top-left at the
;             pointer and moved back to fit on the output; it stays there
;             until moved (window_move, Alt+drag). Maximized or fullscreen
;             it fills the output (fullscreen above top layers; maximized
;             the part layers' exclusive strips leave) and goes back to its
;             place and size after; minimized it leaves the output until
;             window_activate brings it back. The window list
;             (shell/window_list) is told of every toplevel and change.
;   popup     at its offset on its parent, kept on the output, and moved
;             with it; when the parent goes, or a press lands on anything
;             but a popup, it gets done and loses the role (the client
;             then destroys it)
;   layer     against the output's edges by its anchors and margin
;
; The role sets the surface's stacking level (LEVEL_*), which the compositor
; keeps it in. Toplevels are on Server.windows, newest first, for a task list.
; A Window lives in its client's arena: a disconnect frees it with the rest.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/cwp.inc"
%include "inc/cwp_ops.inc"
%include "inc/channel.inc"
%include "inc/backend.inc"
%include "inc/struct_offsets.inc"

extern arena_alloc
extern compositor_add_surface
extern compositor_damage_surface
extern compositor_raise_surface
extern compositor_remove_surface
extern compositor_restack_surface
extern handle_resolve
extern input_focus_surface
extern input_forget_surface
extern msgbuf_write
extern stacking_unmapped
extern window_list_changed
extern window_list_removed

; Events: interface << 16 | event
%define EV_CONFIGURE    (CWP_OBJ_TOPLEVEL << 16 | TOPLEVEL_EVENT_CONFIGURE)
%define EV_CLOSE        (CWP_OBJ_TOPLEVEL << 16 | TOPLEVEL_EVENT_CLOSE)
%define EV_POPUP_DONE   (CWP_OBJ_POPUP << 16 | POPUP_EVENT_DONE)
%define EV_LAYER_CONFIGURE (CWP_OBJ_LAYER << 16 | LAYER_EVENT_CONFIGURE)

section .text

; ---------------------------------------------------------------------------
; window_create
;   Make a surface a window and send it its first configure
;   IN:  rdi = server*, rsi = surface*
;   OUT: rax = 0, -EEXIST if it has a role already, -ENOMEM
; ---------------------------------------------------------------------------
global window_create
window_create:
    PROLOGUE_SAVE rbx, r12, r13
    sub rsp, 8                          ; 16-byte aligned
    mov rbx, rdi
    mov r12, rsi
    call new_role
    test rax, rax
    js .out
    mov r13, rax
    mov rax, [rbx + Server.windows]
    mov [r13 + Window.next], rax
    mov [rbx + Server.windows], r13
    mov eax, [rbx + Server.window_seq]  ; its id in the window list
    inc eax
    mov [rbx + Server.window_seq], rax
    mov [r13 + Window.number], eax

    mov rdi, r12                        ; any size it likes, for now
    xor esi, esi
    xor edx, edx
    call window_configure
    mov rdi, rbx
    mov rsi, r13
    call window_list_changed
    xor eax, eax
.out:
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13

; ---------------------------------------------------------------------------
; window_popup_create
;   Make a surface a popup on another
;   IN:  rdi = server*, rsi = surface*, rdx = parent Surface*, ecx = x,
;        r8d = y (on the parent)
;   OUT: rax = 0, -EEXIST if it has a role already, -EINVAL if it would be
;        its own parent, -ENOMEM
; ---------------------------------------------------------------------------
global window_popup_create
window_popup_create:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14d, ecx
    mov rax, -(EINVAL)
    cmp r13, r12
    je .out
    push r8
    push r8                             ; 16-byte aligned
    call new_role
    pop r8
    pop r8
    test rax, rax
    js .out
    mov dword [rax + Window.kind], ROLE_POPUP
    mov dword [rax + Window.level], LEVEL_POPUP
    mov [rax + Window.parent], r13
    mov [rax + Window.offset_x], r14d
    mov [rax + Window.offset_y], r8d
    mov rdi, rbx
    mov rsi, r12
    call compositor_restack_surface
    xor eax, eax
.out:
    EPILOGUE_RESTORE rbx, r12, r13, r14

; ---------------------------------------------------------------------------
; window_layer_create
;   Make a surface a layer and tell it its size
;   IN:  rdi = server*, rsi = surface*, edx = layer (0 background, 1 bottom,
;        2 top, 3 overlay), ecx = ANCHOR_* bits, r8d = margin
;   OUT: rax = 0, -EEXIST if it has a role already, -EINVAL for no such
;        layer, -ENOMEM
; ---------------------------------------------------------------------------
global window_layer_create
window_layer_create:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov rax, -(EINVAL)
    cmp edx, 3
    ja .out
    lea r13, [rel layer_levels]
    mov r13d, [r13 + rdx * 4]
    mov r14d, ecx
    and r14d, ANCHOR_TOP | ANCHOR_BOTTOM | ANCHOR_LEFT | ANCHOR_RIGHT
    push r8
    push r8                             ; 16-byte aligned
    call new_role
    pop r8
    pop r8
    test rax, rax
    js .out
    mov dword [rax + Window.kind], ROLE_LAYER
    mov [rax + Window.level], r13d
    mov [rax + Window.anchor], r14d
    mov [rax + Window.margin], r8d
    mov rdi, rbx
    mov rsi, r12
    call compositor_restack_surface

    ; Its size: the output's, less the margins, along each pair it spans
    xor esi, esi
    xor edx, edx
    mov rax, [r12 + Surface.output]
    test rax, rax
    jz .sized
    mov rcx, [r12 + Surface.window]
    mov r8d, [rcx + Window.margin]
    add r8d, r8d
    mov ecx, r14d
    and ecx, ANCHOR_LEFT | ANCHOR_RIGHT
    cmp ecx, ANCHOR_LEFT | ANCHOR_RIGHT
    jne .height
    mov esi, [rax + Output.width]
    sub esi, r8d
.height:
    mov ecx, r14d
    and ecx, ANCHOR_TOP | ANCHOR_BOTTOM
    cmp ecx, ANCHOR_TOP | ANCHOR_BOTTOM
    jne .sized
    mov edx, [rax + Output.height]
    sub edx, r8d
.sized:
    mov rdi, r12
    mov r8d, esi
    mov r9d, edx
    mov rax, [r12 + Surface.window]
    mov ecx, [rax + Window.serial]
    inc ecx
    mov [rax + Window.serial], ecx
    mov esi, EV_LAYER_CONFIGURE
    mov edx, 16
    call send_event
    xor eax, eax
.out:
    EPILOGUE_RESTORE rbx, r12, r13, r14

; ---------------------------------------------------------------------------
; window_layer_exclusive
;   Keep a strip along a layer's edge from maximized windows
;   IN:  rdi = server*, rsi = surface*, edx = its width (0: none)
;   OUT: rax = 0, -EINVAL if it is not a layer
; ---------------------------------------------------------------------------
global window_layer_exclusive
window_layer_exclusive:
    mov rax, [rsi + Surface.window]
    test rax, rax
    jz .invalid
    cmp dword [rax + Window.kind], ROLE_LAYER
    jne .invalid
    mov [rax + Window.exclusive], edx
    jmp relayout_maximized
.invalid:
    mov rax, -(EINVAL)
    ret

; ---------------------------------------------------------------------------
; window_destroy
;   The surface loses its role; it stays where it was put, at the normal
;   level
;   IN:  rdi = server*, rsi = surface*
;   OUT: rax = 0, -EINVAL if it has no role
; ---------------------------------------------------------------------------
global window_destroy
window_destroy:
    PROLOGUE_SAVE rbx, r12, r13
    sub rsp, 8                          ; 16-byte aligned
    mov rbx, rdi
    mov r12, rsi
    mov r13, [r12 + Surface.window]
    mov rax, -(EINVAL)
    test r13, r13
    jz .out
    cmp dword [r13 + Window.kind], ROLE_TOPLEVEL
    jne .unlinked
    mov rdi, rbx                        ; gone from the window list
    mov rsi, r13
    call window_list_removed
    lea rcx, [rbx + Server.windows]
.find:
    mov rdx, [rcx]
    test rdx, rdx
    jz .unlinked
    cmp rdx, r13
    je .unlink
    lea rcx, [rdx + Window.next]
    jmp .find
.unlink:
    mov rdx, [r13 + Window.next]
    mov [rcx], rdx
.unlinked:
    mov qword [r12 + Surface.window], 0
    cmp dword [r13 + Window.level], LEVEL_NORMAL
    je .layout
    mov rdi, rbx                        ; back among the windows
    mov rsi, r12
    call compositor_restack_surface
.layout:
    cmp dword [r13 + Window.kind], ROLE_LAYER
    jne .done
    cmp dword [r13 + Window.exclusive], 0
    je .done
    mov rdi, rbx                        ; its strip is free again
    call relayout_maximized
.done:
    xor eax, eax
.out:
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13

; ---------------------------------------------------------------------------
; window_parent_gone
;   A surface is going: every popup on it gets done and loses its role
;   IN:  rdi = server*, rsi = surface*
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global window_parent_gone
window_parent_gone:
    mov rdx, [rsi + Surface.output]
    test rdx, rdx
    jnz end_popups
    xor eax, eax
    ret

; ---------------------------------------------------------------------------
; window_dismiss_popups
;   A press: on a popup it changes nothing; anywhere else every popup gets
;   done and loses its role
;   IN:  rdi = server*, rsi = the surface pressed, 0 for none
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global window_dismiss_popups
window_dismiss_popups:
    test rsi, rsi
    jz .all
    mov rax, [rsi + Surface.window]
    test rax, rax
    jz .all
    cmp dword [rax + Window.kind], ROLE_POPUP
    jne .all
    xor eax, eax
    ret
.all:
    mov rdx, [rdi + Server.outputs]
    xor esi, esi
    test rdx, rdx
    jnz end_popups
    xor eax, eax
    ret

; Popups on output rdx get done and lose their role: those on parent rsi, or
; every one when rsi is 0.
; rdi = server, rsi = parent or 0, rdx = Output* -> rax = 0
end_popups:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, [rdx + Output.surfaces]
.next:
    test r13, r13
    jz .done
    mov r14, [r13 + Surface.z_order_next]   ; before r13 moves
    mov rax, [r13 + Surface.window]
    test rax, rax
    jz .skip
    cmp dword [rax + Window.kind], ROLE_POPUP
    jne .skip
    test r12, r12
    jz .end
    cmp [rax + Window.parent], r12
    jne .skip
.end:
    mov rdi, r13
    mov esi, EV_POPUP_DONE
    mov edx, 4
    call send_event
    mov rdi, rbx
    mov rsi, r13
    call window_destroy
.skip:
    mov r13, r14
    jmp .next
.done:
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12, r13, r14

; ---------------------------------------------------------------------------
; window_set_name
;   Its title or app id
;   IN:  rdi = surface*, esi = 0 title / 1 app id, rdx = UTF-8 bytes,
;        ecx = length
;   OUT: rax = 0, -EINVAL if it has no role or the name is longer than
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
    cmp dword [rax + Window.kind], ROLE_TOPLEVEL
    jne .named
    mov rsi, rax                        ; the window list sees the new name
    mov rdi, [rax + Window.server]
    jmp window_list_changed
.named:
    xor eax, eax
    ret
.invalid:
    mov rax, -(EINVAL)
    ret

; ---------------------------------------------------------------------------
; window_ack_configure
;   IN:  rdi = surface*, esi = serial
;   OUT: rax = 0, -EINVAL if it has no role or no such configure was sent
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
;   Suggest a window's size, with its states; the client answers with
;   ack_configure
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
    mov r11d, [rbx + Window.state]
    and r11d, WINDOW_MAXIMIZED | WINDOW_FULLSCREEN
    mov ecx, [rbx + Window.serial]
    inc ecx
    mov [rbx + Window.serial], ecx
    mov esi, EV_CONFIGURE
    mov edx, 20
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
; window_move
;   Put a surface with a role somewhere else; both places are redrawn
;   IN:  rdi = server*, rsi = surface*, edx = x, ecx = y
;   OUT: rax = 0, -EINVAL if it has no role
; ---------------------------------------------------------------------------
global window_move
window_move:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov r14d, ecx
    mov rax, -(EINVAL)
    mov rcx, [r12 + Surface.window]
    test rcx, rcx
    jz .out
    mov rdi, rbx                        ; where it was
    mov rsi, r12
    call compositor_damage_surface
    mov rcx, [r12 + Surface.window]
    mov [rcx + Window.x], r13d
    mov [rcx + Window.y], r14d
    mov dword [rcx + Window.placed], 1
    mov [r12 + Surface.current + SurfaceState.buf_x], r13d
    mov [r12 + Surface.current + SurfaceState.buf_y], r14d
    mov rdi, rbx                        ; where it is
    mov rsi, r12
    call compositor_damage_surface
    mov rdi, rbx                        ; its popups come along
    mov rsi, r12
    call follow_parent
    xor eax, eax
.out:
    EPILOGUE_RESTORE rbx, r12, r13, r14

; Every popup on a surface that moved goes to its offset again, and theirs.
; rdi = server, rsi = the surface that moved
follow_parent:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov rax, [r12 + Surface.output]
    test rax, rax
    jz .done
    mov r13, [rax + Output.surfaces]
.next:
    test r13, r13
    jz .done
    mov rax, [r13 + Surface.window]
    test rax, rax
    jz .skip
    cmp dword [rax + Window.kind], ROLE_POPUP
    jne .skip
    cmp [rax + Window.parent], r12
    jne .skip
    mov rdi, rbx                        ; where it was
    mov rsi, r13
    call compositor_damage_surface
    mov rdi, rbx
    mov rsi, r13
    call window_commit
    mov rdi, rbx                        ; where it is
    mov rsi, r13
    call compositor_damage_surface
    mov rdi, rbx
    mov rsi, r13
    call follow_parent
.skip:
    mov r13, [r13 + Surface.z_order_next]
    jmp .next
.done:
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12, r13, r14

; ---------------------------------------------------------------------------
; window_maximize
; window_fullscreen
;   Set or clear a window's state; it moves and is asked for its new size
;   IN:  rdi = server*, rsi = surface*, edx = 1 set, 0 clear
;   OUT: rax = 0, -EINVAL if it is not a window
; ---------------------------------------------------------------------------
global window_maximize
window_maximize:
    mov ecx, WINDOW_MAXIMIZED
    jmp set_state

global window_fullscreen
window_fullscreen:
    mov ecx, WINDOW_FULLSCREEN
    jmp set_state

; ---------------------------------------------------------------------------
; window_minimize
;   Off the screen; the keyboard goes on if it had it
;   IN:  rdi = server*, rsi = surface*
;   OUT: rax = 0, -EINVAL if it is not a window
; ---------------------------------------------------------------------------
global window_minimize
window_minimize:
    PROLOGUE_SAVE rbx, r12, r13
    sub rsp, 8                          ; 16-byte aligned
    mov rbx, rdi
    mov r12, rsi
    call toplevel_of
    test rax, rax
    js .out
    mov r13, rax
    test dword [r13 + Window.state], WINDOW_MINIMIZED
    jnz .done
    mov rax, [r12 + Surface.output]
    test rax, rax
    jz .done                            ; not on an output to leave
    mov [r13 + Window.min_output], rax
    or dword [r13 + Window.state], WINDOW_MINIMIZED
    mov rdi, rbx                        ; its popups end
    mov rsi, r12
    call window_parent_gone
    mov rdi, rbx                        ; the keyboard on, while it is still
    mov rsi, r12                        ; among the others
    call stacking_unmapped
    mov rdi, rbx
    mov rsi, r12
    call input_forget_surface
    mov rdi, rbx
    mov rsi, r12
    call compositor_remove_surface
    mov rdi, rbx
    mov rsi, r13
    call window_list_changed
.done:
    xor eax, eax
.out:
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13

; ---------------------------------------------------------------------------
; window_activate
;   Back on the screen if minimized, raised, given the keyboard
;   IN:  rdi = server*, rsi = surface*
;   OUT: rax = 0, -EINVAL if it is not a window
; ---------------------------------------------------------------------------
global window_activate
window_activate:
    PROLOGUE_SAVE rbx, r12, r13
    sub rsp, 8                          ; 16-byte aligned
    mov rbx, rdi
    mov r12, rsi
    call toplevel_of
    test rax, rax
    js .out
    mov r13, rax
    test dword [r13 + Window.state], WINDOW_MINIMIZED
    jz .raise
    and dword [r13 + Window.state], ~WINDOW_MINIMIZED
    mov rdi, [r13 + Window.min_output]
    mov rsi, r12
    call compositor_add_surface
    mov rdi, rbx
    mov rsi, r12
    call compositor_damage_surface
    mov rdi, rbx
    mov rsi, r13
    call window_list_changed
.raise:
    mov rdi, rbx
    mov rsi, r12
    call compositor_raise_surface
    mov rdi, rbx
    mov rsi, r12
    call input_focus_surface
    xor eax, eax
.out:
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13

; ---------------------------------------------------------------------------
; window_commit
;   After a commit: the surface goes where its role puts it
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
    cmp dword [r13 + Window.kind], ROLE_TOPLEVEL
    jne .size
    cmp dword [r13 + Window.placed], 0
    jne .put                            ; a window stays where it is
.size:
    mov rsi, [r12 + Surface.current + SurfaceState.buffer]
    test rsi, rsi
    jz .put                             ; nothing shown to place
    mov rdi, [rbx + Server.buffer_table]
    call handle_resolve
    test rax, rax
    jz .put
    mov rdi, rbx
    mov rsi, r13
    mov edx, [rax + Buffer.width]
    mov ecx, [rax + Buffer.height]
    mov eax, [r13 + Window.kind]
    cmp eax, ROLE_POPUP
    je .popup
    cmp eax, ROLE_LAYER
    je .layer
    call place_at_pointer
    jmp .placed
.popup:
    call place_on_parent
    jmp .placed
.layer:
    call place_by_anchor
.placed:
    mov dword [r13 + Window.placed], 1
.put:
    cmp dword [r13 + Window.placed], 0
    je .out
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

; rsi = surface -> rax = its Window if it is a toplevel, else -EINVAL
toplevel_of:
    mov rax, [rsi + Surface.window]
    test rax, rax
    jz .invalid
    cmp dword [rax + Window.kind], ROLE_TOPLEVEL
    jne .invalid
    ret
.invalid:
    mov rax, -(EINVAL)
    ret

; Maximized or fullscreen, set (edx = 1) or cleared (0): ecx = the state.
; With either it fills the output, fullscreen above top layers; with
; neither it goes back to where and how big it was.
; rdi = server, rsi = surface -> rax = 0, -EINVAL
set_state:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r14d, ecx
    push rdx
    push rdx                            ; 16-byte aligned
    call toplevel_of
    pop rdx
    pop rdx
    test rax, rax
    js .out
    mov r13, rax
    mov eax, [r13 + Window.state]
    test edx, edx
    jz .clear
    test eax, r14d
    jnz .done                           ; set already
    test eax, WINDOW_MAXIMIZED | WINDOW_FULLSCREEN
    jnz .set                            ; its own place is kept already
    mov ecx, [r13 + Window.x]           ; where and how big it was
    mov [r13 + Window.saved_x], ecx
    mov ecx, [r13 + Window.y]
    mov [r13 + Window.saved_y], ecx
    mov dword [r13 + Window.saved_w], 0
    mov dword [r13 + Window.saved_h], 0
    mov rsi, [r12 + Surface.current + SurfaceState.buffer]
    test rsi, rsi
    jz .set
    mov rdi, [rbx + Server.buffer_table]
    call handle_resolve
    test rax, rax
    jz .set
    mov ecx, [rax + Buffer.width]
    mov [r13 + Window.saved_w], ecx
    mov ecx, [rax + Buffer.height]
    mov [r13 + Window.saved_h], ecx
.set:
    or [r13 + Window.state], r14d
    jmp .apply
.clear:
    test eax, r14d
    jz .done                            ; clear already
    not r14d
    and [r13 + Window.state], r14d
.apply:
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call apply_state
    mov rdi, rbx
    mov rsi, r13
    call window_list_changed
.done:
    xor eax, eax
.out:
    EPILOGUE_RESTORE rbx, r12, r13, r14

; Level, place and asked-for size from a window's states: fullscreen fills
; the output above the top layers; maximized fills what the layers' strips
; leave; neither goes back to where and how big it was.
; rdi = server, rsi = surface, rdx = its Window
apply_state:
    PROLOGUE_SAVE rbx, r12, r13
    sub rsp, 8                          ; 16-byte aligned
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov eax, LEVEL_NORMAL
    test dword [r13 + Window.state], WINDOW_FULLSCREEN
    jz .level
    mov eax, LEVEL_FULLSCREEN
.level:
    cmp eax, [r13 + Window.level]
    je .place
    mov [r13 + Window.level], eax
    mov rdi, rbx
    mov rsi, r12
    call compositor_restack_surface
.place:
    test dword [r13 + Window.state], WINDOW_MAXIMIZED | WINDOW_FULLSCREEN
    jz .back
    mov rax, [r12 + Surface.output]
    test rax, rax
    jnz .output
    mov rax, [r13 + Window.min_output]  ; minimized: the one it left
    test rax, rax
    jnz .output
    mov rax, [rbx + Server.outputs]
    test rax, rax
    jz .done
.output:
    test dword [r13 + Window.state], WINDOW_FULLSCREEN
    jnz .whole
    mov rdi, rbx
    mov rsi, rax
    call usable_area
    mov r9d, r8d
    mov r8d, ecx
    mov ecx, edx
    mov edx, eax
    jmp .go
.whole:
    mov edx, [rax + Output.x]
    mov ecx, [rax + Output.y]
    mov r8d, [rax + Output.width]
    mov r9d, [rax + Output.height]
    jmp .go
.back:
    mov edx, [r13 + Window.saved_x]
    mov ecx, [r13 + Window.saved_y]
    mov r8d, [r13 + Window.saved_w]
    mov r9d, [r13 + Window.saved_h]
.go:
    push r8
    push r9
    mov rdi, rbx
    mov rsi, r12
    call window_move
    pop rdx
    pop rsi
    mov rdi, r12
    call window_configure
.done:
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13

; Every maximized window to the area the layers' strips now leave.
; rdi = server -> rax = 0
relayout_maximized:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, [rbx + Server.windows]
.next:
    test r12, r12
    jz .done
    mov eax, [r12 + Window.state]
    and eax, WINDOW_MAXIMIZED | WINDOW_FULLSCREEN
    cmp eax, WINDOW_MAXIMIZED
    jne .skip
    mov rdi, rbx
    mov rsi, [r12 + Window.surface]
    mov rdx, r12
    call apply_state
.skip:
    mov r12, [r12 + Window.next]
    jmp .next
.done:
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12

; The part of an output the layers' exclusive strips leave.
; rdi = server, rsi = Output* -> eax = x, edx = y, ecx = width, r8d = height
usable_area:
    mov eax, [rsi + Output.x]
    mov edx, [rsi + Output.y]
    mov ecx, eax
    add ecx, [rsi + Output.width]       ; the right edge, for now
    mov r8d, edx
    add r8d, [rsi + Output.height]      ; the bottom edge
    mov r9, [rsi + Output.surfaces]
.next:
    test r9, r9
    jz .done
    mov r10, [r9 + Surface.window]
    test r10, r10
    jz .skip
    cmp dword [r10 + Window.kind], ROLE_LAYER
    jne .skip
    mov r11d, [r10 + Window.exclusive]
    test r11d, r11d
    jz .skip
    add r11d, [r10 + Window.margin]
    mov edi, [r10 + Window.anchor]
    and edi, ANCHOR_TOP | ANCHOR_BOTTOM
    cmp edi, ANCHOR_TOP
    jne .not_top
    mov edi, [rsi + Output.y]
    add edi, r11d
    cmp edx, edi
    cmovl edx, edi
    jmp .skip
.not_top:
    cmp edi, ANCHOR_BOTTOM
    jne .sides
    mov edi, [rsi + Output.y]
    add edi, [rsi + Output.height]
    sub edi, r11d
    cmp r8d, edi
    cmovg r8d, edi
    jmp .skip
.sides:
    mov edi, [r10 + Window.anchor]
    and edi, ANCHOR_LEFT | ANCHOR_RIGHT
    cmp edi, ANCHOR_LEFT
    jne .not_left
    mov edi, [rsi + Output.x]
    add edi, r11d
    cmp eax, edi
    cmovl eax, edi
    jmp .skip
.not_left:
    cmp edi, ANCHOR_RIGHT
    jne .skip
    mov edi, [rsi + Output.x]
    add edi, [rsi + Output.width]
    sub edi, r11d
    cmp ecx, edi
    cmovg ecx, edi
.skip:
    mov r9, [r9 + Surface.z_order_next]
    jmp .next
.done:
    sub ecx, eax
    sub r8d, edx
    ret

; A Window for the surface, at the normal level, as a toplevel until told.
; rdi = server, rsi = surface -> rax = Window*, -EEXIST, -ENOMEM
new_role:
    PROLOGUE_SAVE rbx, r12
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
    mov rdi, rax
    mov rdx, rax
    xor eax, eax
    mov ecx, Window_size
    rep stosb
    mov rax, rdx
    mov [rax + Window.server], rbx
    mov [rax + Window.surface], r12
    mov [r12 + Surface.window], rax
.out:
    EPILOGUE_RESTORE rbx, r12
.oom:
    mov rax, -(ENOMEM)
    jmp .out

; The output for a place: the surface's, else the first
; rdi = server, rsi = window -> r8 = Output*, 0 if none
%macro OUTPUT_OF 0
    mov r8, [rsi + Window.surface]
    mov r8, [r8 + Surface.output]
    test r8, r8
    jnz %%have
    mov r8, [rdi + Server.outputs]
%%have:
%endmacro

; eax = x, r10d = y of a w x h rectangle (edx, ecx) -> both moved back onto
; output r8 as far as it goes, into Window.x / y of rsi
keep_on_output:
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
    ret

; Top-left at the pointer (the output's centre with no seat).
; rdi = server, rsi = window, edx = width, ecx = height
place_at_pointer:
    OUTPUT_OF
    test r8, r8
    jz .done
    mov r9, [rdi + Server.input_seat]
    test r9, r9
    jz .centre
    mov eax, [r9 + InputSeat.x]
    mov r10d, [r9 + InputSeat.y]
    jmp keep_on_output
.centre:
    mov eax, [r8 + Output.width]
    shr eax, 1
    add eax, [r8 + Output.x]
    mov r10d, [r8 + Output.height]
    shr r10d, 1
    add r10d, [r8 + Output.y]
    jmp keep_on_output
.done:
    ret

; At its offset on its parent.
; rdi = server, rsi = window, edx = width, ecx = height
place_on_parent:
    OUTPUT_OF
    test r8, r8
    jz .done
    mov r9, [rsi + Window.parent]
    mov eax, [r9 + Surface.current + SurfaceState.buf_x]
    add eax, [rsi + Window.offset_x]
    mov r10d, [r9 + Surface.current + SurfaceState.buf_y]
    add r10d, [rsi + Window.offset_y]
    jmp keep_on_output
.done:
    ret

; Against the edges it is anchored to, centred along a pair it is anchored
; to neither or both of.
; rdi = server, rsi = window, edx = width, ecx = height
place_by_anchor:
    OUTPUT_OF
    test r8, r8
    jz .done
    mov r9d, [rsi + Window.anchor]
    mov r11d, [rsi + Window.margin]

    mov eax, r9d                        ; x
    and eax, ANCHOR_LEFT | ANCHOR_RIGHT
    cmp eax, ANCHOR_LEFT
    je .left
    cmp eax, ANCHOR_RIGHT
    je .right
    mov eax, [r8 + Output.width]
    sub eax, edx
    sar eax, 1
    add eax, [r8 + Output.x]
    jmp .x_done
.left:
    mov eax, [r8 + Output.x]
    add eax, r11d
    jmp .x_done
.right:
    mov eax, [r8 + Output.x]
    add eax, [r8 + Output.width]
    sub eax, edx
    sub eax, r11d
.x_done:
    mov [rsi + Window.x], eax

    mov eax, r9d                        ; y
    and eax, ANCHOR_TOP | ANCHOR_BOTTOM
    cmp eax, ANCHOR_TOP
    je .top
    cmp eax, ANCHOR_BOTTOM
    je .bottom
    mov eax, [r8 + Output.height]
    sub eax, ecx
    sar eax, 1
    add eax, [r8 + Output.y]
    jmp .y_done
.top:
    mov eax, [r8 + Output.y]
    add eax, r11d
    jmp .y_done
.bottom:
    mov eax, [r8 + Output.y]
    add eax, [r8 + Output.height]
    sub eax, ecx
    sub eax, r11d
.y_done:
    mov [rsi + Window.y], eax
.done:
    ret

; An event to the surface's client: (surface, a, b, c, d), edx bytes of it.
; rdi = surface, esi = interface << 16 | event, edx = length, ecx = a,
; r8d = b, r9d = c, r11d = d
send_event:
    PROLOGUE
    sub rsp, 48                         ; header at 0, payload at 16
    mov rax, [rdi + Surface.client]
    test rax, rax
    jz .out
    mov r10d, [rdi + Surface.id]
    mov [rsp + 16], r10d
    mov [rsp + 20], ecx
    mov [rsp + 24], r8d
    mov [rsp + 28], r9d
    mov [rsp + 32], r11d
    mov r10d, esi
    shr r10d, 16
    mov [rsp + MsgHdr.obj], r10d
    mov [rsp + MsgHdr.opcode], si
    mov word [rsp + MsgHdr.flags], CWP_MSG_FLAG_IS_EVENT
    mov [rsp + MsgHdr.len], edx
    mov rdi, [rax + Client.rx_ring]
    mov rsi, rsp
    lea rdx, [rsp + 16]
    call msgbuf_write
.out:
    EPILOGUE

section .rodata
; cw_layer.layer -> stacking level
layer_levels:   dd LEVEL_BACKGROUND, LEVEL_BOTTOM, LEVEL_TOP, LEVEL_OVERLAY
