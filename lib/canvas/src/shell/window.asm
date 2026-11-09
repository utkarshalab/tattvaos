; ============================================================================
; Window — Shell Roles: Toplevels, Popups, Layers (proto/canvas-shell.cwp)
; ============================================================================
; A client gives a surface a role; the server then owns where it goes, and
; the x, y of attach are ignored. Each commit puts the surface where its role
; says:
;
;   toplevel  placed the first time it shows a buffer, its top-left at the
;             pointer and moved back to fit on the output; it stays there
;             until moved (window_move, Alt+drag); it is on the output its
;             middle is on, the one under the pointer when it is placed. Maximized or fullscreen
;             it fills the output (fullscreen above top layers; maximized
;             the part layers' exclusive strips leave) and goes back to its
;             place and size after. It is on the output only while it is
;             not minimized and its workspace is the one shown; activating
;             it brings it back, showing its workspace. The window list
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
extern surface_logical_size
extern compositor_move_to_output
extern compositor_output_at
extern compositor_raise_surface
extern compositor_remove_surface
extern compositor_restack_surface
extern handle_resolve
extern input_focus_surface
extern input_forget_surface
extern msgbuf_write
extern stacking_focus_any
extern stacking_unmapped
extern window_list_changed
extern window_list_removed
extern window_list_workspace
extern switcher_forget
extern ut_time_now_ns

; Events: interface << 16 | event
%define EV_CONFIGURE    (CWP_OBJ_TOPLEVEL << 16 | TOPLEVEL_EV_CONFIGURE)
%define EV_CLOSE        (CWP_OBJ_TOPLEVEL << 16 | TOPLEVEL_EV_CLOSE)
%define EV_POPUP_DONE   (CWP_OBJ_POPUP << 16 | POPUP_EV_DONE)
%define EV_LAYER_CONFIGURE (CWP_OBJ_LAYER << 16 | LAYER_EV_CONFIGURE)

; refresh_visible: what it may do
%define SHOW    1
%define HIDE    2

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
    mov eax, [rbx + Server.workspace]   ; on the workspace shown
    mov [r13 + Window.workspace], eax

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
    mov rdi, r12
    call layer_configure
    xor eax, eax
.out:
    EPILOGUE_RESTORE rbx, r12, r13, r14

; ---------------------------------------------------------------------------
; window_layer_set_output
;   A layer to another output, sized and anchored for it there; the
;   maximized windows of both are laid out again
;   IN:  rdi = server*, rsi = surface*, edx = the output's number, 0 the first
;   OUT: rax = 0, -EINVAL if it is not a layer or there is no such output
; ---------------------------------------------------------------------------
global window_layer_set_output
window_layer_set_output:
    PROLOGUE_SAVE rbx, r12, r13
    sub rsp, 8                          ; 16-byte aligned
    mov rbx, rdi
    mov r12, rsi
    mov rax, -(EINVAL)
    mov rcx, [r12 + Surface.window]
    test rcx, rcx
    jz .out
    cmp dword [rcx + Window.kind], ROLE_LAYER
    jne .out
    mov r13, [rbx + Server.outputs]
.find:
    test r13, r13
    jz .out
    test edx, edx
    jz .found
    dec edx
    mov r13, [r13 + Output.next]
    jmp .find
.found:
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call layer_to_output
    mov rdi, rbx
    call relayout_maximized
    xor eax, eax
.out:
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13

; ---------------------------------------------------------------------------
; window_output_gone
;   An output was taken out of the layout: everything on it goes to another.
;   A window keeps its place on the output, kept on the new one (and its
;   place before it was maximized), maximized or fullscreen fills the new
;   one; a hidden or minimized one comes back there; a layer is sized and
;   anchored there; popups follow their parents; maximized windows are laid
;   out again.
;   IN:  rdi = server*, rsi = the Output* gone, rdx = the Output* they go to
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global window_output_gone
window_output_gone:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, 8                          ; 16-byte aligned
    mov rbx, rdi
    mov r13, rsi
    mov r14, rdx
    mov r12, [rbx + Server.windows]
.window:
    test r12, r12
    jz .others
    mov r15, [r12 + Window.surface]
    mov dword [rsp], 0                  ; 1: it was the gone one's
    cmp [r12 + Window.min_output], r13
    jne .kept
    mov [r12 + Window.min_output], r14  ; hidden: it comes back there
    mov dword [rsp], 1
.kept:
    mov rax, [r15 + Surface.output]
    test rax, rax
    jz .hidden
    cmp rax, r13
    jne .next                           ; shown elsewhere
    mov rdi, r12
    call shift_window
    jmp .move_window
.hidden:
    cmp dword [rsp], 0
    je .next
    mov rdi, r12
    call shift_window
    jmp .next
.move_window:
    mov rdi, rbx
    mov rsi, r15
    mov rdx, r14
    call compositor_move_to_output
    test dword [r12 + Window.state], WINDOW_MAXIMIZED | WINDOW_FULLSCREEN
    jz .plain
    mov rdi, rbx                        ; filling the new one
    mov rsi, r15
    mov rdx, r12
    call apply_state
    jmp .next
.plain:
    mov rdi, rbx                        ; its popups come along
    mov rsi, r15
    mov edx, [r12 + Window.x]
    mov ecx, [r12 + Window.y]
    call window_move
.next:
    mov r12, [r12 + Window.next]
    jmp .window
.others:
    mov r12, [rbx + Server.stack]       ; layers, and anything left
.surface:
    test r12, r12
    jz .done
    cmp [r12 + Surface.output], r13
    jne .next_surface
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r14
    mov rax, [r12 + Surface.window]
    test rax, rax
    jz .move
    cmp dword [rax + Window.kind], ROLE_LAYER
    jne .move
    call layer_to_output
    jmp .next_surface
.move:
    call compositor_move_to_output
.next_surface:
    mov r12, [r12 + Surface.z_order_next]
    jmp .surface
.done:
    mov rdi, rbx
    call relayout_maximized
    xor eax, eax
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15

; A layer to an output: sized and anchored for it there, redrawn.
; rdi = server, rsi = surface, rdx = Output*
layer_to_output:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    call compositor_move_to_output      ; redrawn where it was
    mov rdi, r12
    call layer_configure
    mov rdi, rbx                        ; where its anchors say there
    mov rsi, r12
    call window_commit
    mov rdi, rbx
    mov rsi, r12
    call compositor_damage_surface
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12

; window_output_gone's: a window's place, and its place before it was
; maximized, from output r13 to r14, the same distance from its corner and
; kept at least SHIFT_KEEP on it. rdi = Window*
%define SHIFT_KEEP  32
shift_window:
    mov ecx, [r14 + Output.x]
    sub ecx, [r13 + Output.x]
    mov edx, [r14 + Output.y]
    sub edx, [r13 + Output.y]
    add [rdi + Window.x], ecx
    add [rdi + Window.y], edx
    add [rdi + Window.saved_x], ecx
    add [rdi + Window.saved_y], edx
    mov r8d, [r14 + Output.x]           ; how far right and down it may be
    add r8d, [r14 + Output.width]
    sub r8d, SHIFT_KEEP
    mov r9d, [r14 + Output.y]
    add r9d, [r14 + Output.height]
    sub r9d, SHIFT_KEEP
%macro KEEP_ON 3                        ; field, the far limit, the near one
    mov eax, [rdi + Window.%1]
    cmp eax, %2
    cmovg eax, %2
    cmp eax, [r14 + Output.%3]
    cmovl eax, [r14 + Output.%3]
    mov [rdi + Window.%1], eax
%endmacro
    KEEP_ON x, r8d, x
    KEEP_ON saved_x, r8d, x
    KEEP_ON y, r9d, y
    KEEP_ON saved_y, r9d, y
    ret

; A layer's size in a configure: its output's, less the margins, along each
; pair of edges it is anchored to (0 along the others: its own choice).
; rdi = surface
layer_configure:
    xor esi, esi
    xor edx, edx
    mov rax, [rdi + Surface.output]
    test rax, rax
    jz .sized
    mov rcx, [rdi + Surface.window]
    mov r8d, [rcx + Window.margin]
    add r8d, r8d
    mov r9d, [rcx + Window.anchor]
    mov ecx, r9d
    and ecx, ANCHOR_LEFT | ANCHOR_RIGHT
    cmp ecx, ANCHOR_LEFT | ANCHOR_RIGHT
    jne .height
    mov esi, [rax + Output.width]
    sub esi, r8d
.height:
    mov ecx, r9d
    and ecx, ANCHOR_TOP | ANCHOR_BOTTOM
    cmp ecx, ANCHOR_TOP | ANCHOR_BOTTOM
    jne .sized
    mov edx, [rax + Output.height]
    sub edx, r8d
.sized:
    mov r8d, esi
    mov r9d, edx
    mov rax, [rdi + Surface.window]
    mov ecx, [rax + Window.serial]
    inc ecx
    mov [rax + Window.serial], ecx
    mov esi, EV_LAYER_CONFIGURE
    mov edx, 16
    jmp send_event

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
    mov rdi, r12                        ; and from an Alt+Tab
    call switcher_forget
    mov rcx, [rbx + Server.windows]     ; its children belong to none now
.orphan:
    test rcx, rcx
    jz .orphaned
    cmp [rcx + Window.transient], r12
    jne .next_orphan
    mov qword [rcx + Window.transient], 0
.next_orphan:
    mov rcx, [rcx + Window.next]
    jmp .orphan
.orphaned:
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

; Popups get done and lose their role, on any output: those on parent rsi,
; or every one when rsi is 0; rdx is an output, there being a screen.
; rdi = server, rsi = parent or 0, rdx = Output* -> rax = 0
end_popups:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, [rbx + Server.stack]
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
    push rbx
    mov rbx, rax
    mov rdi, [rbx + Window.server]      ; its bar shows the title
    mov rsi, [rbx + Window.surface]
    cmp dword [rbx + Window.decorated], 0
    je .listed
    call compositor_damage_surface
.listed:
    mov rdi, [rbx + Window.server]      ; the window list sees the new name
    mov rsi, rbx
    call window_list_changed
    pop rbx
    xor eax, eax
    ret
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
%macro LIMIT 3                          ; the size, its min, its max field
    test %1, %1                         ; 0: the client picks; left so
    jz %%done
    mov eax, [rbx + Window.%2]
    test eax, eax
    jz %%no_min
    cmp %1, eax
    cmovb %1, eax
%%no_min:
    mov eax, [rbx + Window.%3]
    test eax, eax
    jz %%done
    cmp %1, eax
    cmova %1, eax
%%done:
%endmacro
    LIMIT esi, min_w, max_w             ; inside its limits (WIN-08)
    LIMIT edx, min_h, max_h
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
;   Put a surface with a role somewhere else; both places are redrawn. Its
;   popups and the windows that belong to it (set_parent) move with it.
;   IN:  rdi = server*, rsi = surface*, edx = x, ecx = y
;   OUT: rax = 0, -EINVAL if it has no role
; ---------------------------------------------------------------------------
global window_move
window_move:
    PROLOGUE_SAVE rbx, r12, r13, r14
    sub rsp, 16                         ; how far it moves; 16-byte aligned
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov r14d, ecx
    mov rax, -(EINVAL)
    mov rcx, [r12 + Surface.window]
    test rcx, rcx
    jz .out
    mov eax, r13d
    sub eax, [rcx + Window.x]
    mov [rsp], eax
    mov eax, r14d
    sub eax, [rcx + Window.y]
    mov [rsp + 4], eax
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
    mov rdi, rbx                        ; on the output it is now on
    mov rsi, r12
    call follow_output
    mov rdi, rbx                        ; its popups come along
    mov rsi, r12
    call follow_parent
    mov r13, [rbx + Server.windows]     ; and its children (WIN-10, WIN-11)
.child:
    test r13, r13
    jz .moved
    cmp [r13 + Window.transient], r12
    jne .next_child
    cmp dword [r13 + Window.placed], 0
    je .next_child
    mov rdi, rbx
    mov rsi, [r13 + Window.surface]
    mov edx, [r13 + Window.x]
    add edx, [rsp]
    mov ecx, [r13 + Window.y]
    add ecx, [rsp + 4]
    call window_move
.next_child:
    mov r13, [r13 + Window.next]
    jmp .child
.moved:
    xor eax, eax
.out:
    add rsp, 16
    EPILOGUE_RESTORE rbx, r12, r13, r14

; Every popup on a surface that moved goes to its offset again, and theirs.
; rdi = server, rsi = the surface that moved
follow_parent:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    cmp qword [r12 + Surface.output], 0
    je .done
    mov r13, [rbx + Server.stack]
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
    or dword [r13 + Window.state], WINDOW_MINIMIZED
    mov rdi, rbx
    mov rsi, r13
    mov edx, SHOW | HIDE
    call refresh_visible
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
;   Its workspace shown, back on the screen if minimized, raised, given the
;   keyboard
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
    mov esi, [r13 + Window.workspace]
    cmp esi, [rbx + Server.workspace]
    je .here
    mov rdi, rbx
    call window_switch_workspace
.here:
    test dword [r13 + Window.state], WINDOW_MINIMIZED
    jz .raise
    and dword [r13 + Window.state], ~WINDOW_MINIMIZED
    mov rdi, rbx
    mov rsi, r13
    mov edx, SHOW | HIDE
    call refresh_visible
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
; window_raise
;   A surface to the top of its level, and a window's children (set_parent)
;   above it, theirs above them
;   IN:  rdi = server*, rsi = surface*
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global window_raise
window_raise:
    PROLOGUE_SAVE rbx, r12, r13
    sub rsp, 8                          ; 16-byte aligned
    mov rbx, rdi
    mov r12, rsi
    test r12, r12
    jz .out
    call compositor_raise_surface
    mov r13, [rbx + Server.windows]     ; each child, raised with its own
.child:
    test r13, r13
    jz .out
    cmp [r13 + Window.transient], r12
    jne .next
    mov rdi, rbx
    mov rsi, [r13 + Window.surface]
    call window_raise
.next:
    mov r13, [r13 + Window.next]
    jmp .child
.out:
    xor eax, eax
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13

; ---------------------------------------------------------------------------
; window_modal_target
;   Where the keyboard goes when it would go to a surface: to a modal child
;   of it on the screen (and that one's, in turn), else the surface itself
;   IN:  rdi = surface*, or 0
;   OUT: rax = the surface to have it (0 for 0)
; ---------------------------------------------------------------------------
global window_modal_target
window_modal_target:
    mov rax, rdi
.again:
    test rax, rax
    jz .done
    mov rcx, [rax + Surface.window]
    test rcx, rcx
    jz .done
    mov rcx, [rcx + Window.server]
    mov rcx, [rcx + Server.windows]
.child:
    test rcx, rcx
    jz .done
    cmp [rcx + Window.transient], rax
    jne .next
    cmp dword [rcx + Window.modal], 0
    je .next
    mov rdx, [rcx + Window.surface]
    cmp qword [rdx + Surface.output], 0
    je .next                            ; not on the screen
    mov rax, rdx
    jmp .again
.next:
    mov rcx, [rcx + Window.next]
    jmp .child
.done:
    ret

; ---------------------------------------------------------------------------
; window_may_take_keyboard
;   May a window just shown take the keyboard (WIN-12)? Not when it belongs
;   to another client than the one with the keyboard and the user pressed a
;   key or button within FOCUS_GUARD_NS: they are busy there. Surfaces with
;   no window role, popups and layers may.
;   IN:  rdi = server*, rsi = surface*
;   OUT: rax = 1 may, 0 may not
; ---------------------------------------------------------------------------
%define FOCUS_GUARD_NS  1000000000
global window_may_take_keyboard
window_may_take_keyboard:
    push rbx
    mov eax, 1
    mov rcx, [rsi + Surface.window]
    test rcx, rcx
    jz .out
    cmp dword [rcx + Window.kind], ROLE_TOPLEVEL
    jne .out
    mov rbx, [rdi + Server.input_seat]
    test rbx, rbx
    jz .out
    mov rdx, [rbx + InputSeat.keyboard_focus]
    test rdx, rdx
    jz .out                             ; nothing has it
    mov r8, [rdx + Surface.client]
    cmp r8, [rsi + Surface.client]
    je .out                             ; the same client's
    mov r8, [rbx + InputSeat.last_input]
    test r8, r8
    jz .out                             ; nothing pressed yet
    call ut_time_now_ns
    sub rax, [rbx + InputSeat.last_input]
    cmp rax, FOCUS_GUARD_NS
    setae al
    movzx eax, al
.out:
    pop rbx
    ret

; ---------------------------------------------------------------------------
; window_attention
;   A window wants the user (WIN-14): marked urgent for the window list,
;   unless it has the keyboard already
;   IN:  rdi = server*, rsi = surface*
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global window_attention
window_attention:
    mov rcx, [rsi + Surface.window]
    test rcx, rcx
    jz .out
    cmp dword [rcx + Window.kind], ROLE_TOPLEVEL
    jne .out
    mov rax, [rdi + Server.input_seat]
    test rax, rax
    jz .mark
    cmp [rax + InputSeat.keyboard_focus], rsi
    je .out
.mark:
    test dword [rcx + Window.state], WINDOW_URGENT
    jnz .out
    or dword [rcx + Window.state], WINDOW_URGENT
    mov rsi, rcx
    jmp window_list_changed
.out:
    xor eax, eax
    ret

; ---------------------------------------------------------------------------
; window_set_parent
;   A toplevel belongs to another (WIN-11): on its workspace from now on,
;   placed on it when it first shows. 0: belongs to none.
;   IN:  rdi = server*, rsi = surface* (a toplevel), rdx = the parent
;        surface* (a toplevel), or 0
;   OUT: rax = 0, -EINVAL if that would make a loop
; ---------------------------------------------------------------------------
global window_set_parent
window_set_parent:
    PROLOGUE_SAVE rbx, r12, r13
    sub rsp, 8                          ; 16-byte aligned
    mov rbx, rdi
    mov r12, rsi
    mov r13, [r12 + Surface.window]
    mov rax, rdx                        ; no loop: the parent's own parents
.up:                                    ; never reach this one
    test rax, rax
    jz .fine
    cmp rax, r12
    je .loop
    mov rax, [rax + Surface.window]
    mov rax, [rax + Window.transient]
    jmp .up
.fine:
    mov [r13 + Window.transient], rdx
    test rdx, rdx
    jz .done
    mov rax, [rdx + Surface.window]     ; on its parent's workspace
    mov edx, [rax + Window.workspace]
    mov rdi, rbx
    mov rsi, r12
    call window_move_to_workspace
.done:
    xor eax, eax
.out:
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13
.loop:
    mov rax, -(EINVAL)
    jmp .out

; ---------------------------------------------------------------------------
; window_set_decorated
;   The server draws its title bar, or stops
;   IN:  rdi = server*, rsi = surface*, edx = 1 on, 0 off
;   OUT: rax = 0, -EINVAL if it is not a window
; ---------------------------------------------------------------------------
global window_set_decorated
window_set_decorated:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    xor r14d, r14d
    test edx, edx
    setnz r14b
    call toplevel_of
    test rax, rax
    js .out
    mov r13, rax
    mov rdi, rbx                        ; where the bar was, if it was
    mov rsi, r12
    call compositor_damage_surface
    mov [r13 + Window.decorated], r14d
    mov rdi, rbx                        ; where it is, if it is
    mov rsi, r12
    call compositor_damage_surface
    xor eax, eax
.out:
    EPILOGUE_RESTORE rbx, r12, r13, r14

; ---------------------------------------------------------------------------
; window_switch_workspace
;   Show another workspace: its windows come on the screen, the others go;
;   with nothing left holding the keyboard, the topmost window takes it
;   IN:  rdi = server*, esi = index, 0 to WORKSPACES - 1
;   OUT: rax = 0, -EINVAL for no such workspace
; ---------------------------------------------------------------------------
global window_switch_workspace
window_switch_workspace:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov rax, -(EINVAL)
    cmp esi, WORKSPACES
    jae .out
    cmp esi, [rbx + Server.workspace]
    je .same
    mov esi, esi
    mov [rbx + Server.workspace], rsi
    ; Those coming first, so the keyboard has somewhere to go
    mov r12, [rbx + Server.windows]
.show:
    test r12, r12
    jz .hide_all
    mov rdi, rbx
    mov rsi, r12
    mov edx, SHOW
    call refresh_visible
    mov r12, [r12 + Window.next]
    jmp .show
.hide_all:
    mov r12, [rbx + Server.windows]
.hide:
    test r12, r12
    jz .shown
    mov rdi, rbx
    mov rsi, r12
    mov edx, HIDE
    call refresh_visible
    mov r12, [r12 + Window.next]
    jmp .hide
.shown:
    mov rdi, rbx
    call stacking_focus_any
    mov rdi, rbx
    call window_list_workspace
.same:
    xor eax, eax
.out:
    EPILOGUE_RESTORE rbx, r12

; ---------------------------------------------------------------------------
; window_move_to_workspace
;   IN:  rdi = server*, rsi = surface*, edx = index
;   OUT: rax = 0, -EINVAL if it is not a window or no such workspace
; ---------------------------------------------------------------------------
global window_move_to_workspace
window_move_to_workspace:
    PROLOGUE_SAVE rbx, r12, r13
    sub rsp, 8                          ; 16-byte aligned
    mov rbx, rdi
    mov r12, rsi
    cmp edx, WORKSPACES
    jae .invalid
    push rdx
    push rdx                            ; 16-byte aligned
    call toplevel_of
    pop rdx
    pop rdx
    test rax, rax
    js .out
    mov r13, rax
    mov [r13 + Window.workspace], edx
    mov [rsp], edx
    mov rdi, rbx
    mov rsi, r13
    mov edx, SHOW | HIDE
    call refresh_visible
    mov rdi, rbx
    mov rsi, r13
    call window_list_changed
    mov r13, [rbx + Server.windows]     ; its children go with it (WIN-11)
.child:
    test r13, r13
    jz .moved
    cmp [r13 + Window.transient], r12
    jne .next_child
    mov rdi, rbx
    mov rsi, [r13 + Window.surface]
    mov edx, [rsp]
    call window_move_to_workspace
.next_child:
    mov r13, [r13 + Window.next]
    jmp .child
.moved:
    xor eax, eax
.out:
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13
.invalid:
    mov rax, -(EINVAL)
    jmp .out

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
    mov rdi, r12                        ; its size on the screen
    mov rsi, rax
    call surface_logical_size
    mov ecx, edx
    mov edx, eax
    mov rdi, rbx
    mov rsi, r13
    mov eax, [r13 + Window.kind]
    cmp eax, ROLE_POPUP
    je .popup
    cmp eax, ROLE_LAYER
    je .layer
    mov rax, [r13 + Window.transient]   ; a child: centred on its parent
    test rax, rax
    jz .at_pointer
    cmp qword [rax + Surface.output], 0
    je .at_pointer                      ; parent off the screen
    call place_on_transient
    jmp .window_placed
.at_pointer:
    call place_at_pointer
.window_placed:
    mov dword [r13 + Window.placed], 1
    call put
    mov rdi, rbx                        ; on the output it is on
    mov rsi, r12
    call follow_output
    mov rdi, rbx                        ; all of it new, its bar too: the
    mov rsi, r12                        ; client damaged only its own pixels
    call compositor_damage_surface
    jmp .out
.popup:
    push rdx
    push rcx
    mov rax, [r13 + Window.parent]      ; on its parent's output
    mov rdx, [rax + Surface.output]
    mov rdi, rbx
    mov rsi, r12
    call compositor_move_to_output
    pop rcx
    pop rdx
    mov rdi, rbx
    mov rsi, r13
    call place_on_parent
    jmp .placed
.layer:
    call place_by_anchor
.placed:
    mov dword [r13 + Window.placed], 1
.put:
    cmp dword [r13 + Window.placed], 0
    je .out
    call put
    cmp dword [r13 + Window.decorated], 0
    je .out
    mov rsi, [r12 + Surface.current + SurfaceState.buffer]
    test rsi, rsi
    jz .out
    mov rdi, [rbx + Server.buffer_table]
    call handle_resolve
    test rax, rax
    jz .out
    mov rdi, r12
    mov rsi, rax
    call surface_logical_size
    cmp eax, [r13 + Window.bar_w]
    je .out
    mov [r13 + Window.bar_w], eax       ; a new width: the bar again
    mov rdi, rbx
    mov rsi, r12
    call compositor_damage_surface
.out:
    xor eax, eax
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13

; ---------------------------------------------------------------------------
; Local
; ---------------------------------------------------------------------------

; A toplevel is on its output while it is not minimized and its workspace
; is shown. Bring it on or take it off to match, as edx allows: SHOW, HIDE.
; Taken off, its popups end, the keyboard goes on if it had it, and the
; output it left is kept to come back to.
; rdi = server, rsi = Window*, edx = SHOW | HIDE -> rax = 0
refresh_visible:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, [r12 + Window.surface]
    mov r14d, edx
    cmp dword [r12 + Window.kind], ROLE_TOPLEVEL
    jne .done
    xor eax, eax                        ; wanted on the screen
    test dword [r12 + Window.state], WINDOW_MINIMIZED
    jnz .wanted
    mov ecx, [r12 + Window.workspace]
    cmp ecx, [rbx + Server.workspace]
    jne .wanted
    mov eax, 1
.wanted:
    xor ecx, ecx                        ; on it now
    cmp qword [r13 + Surface.output], 0
    setne cl
    cmp eax, ecx
    je .done
    test eax, eax
    jz .hide
    test r14d, SHOW
    jz .done
    mov rdi, [r12 + Window.min_output]
    test rdi, rdi
    jz .done
    mov rsi, r13
    call compositor_add_surface
    mov rdi, rbx
    mov rsi, r13
    call compositor_damage_surface
    jmp .done
.hide:
    test r14d, HIDE
    jz .done
    mov rax, [r13 + Surface.output]
    mov [r12 + Window.min_output], rax
    mov rdi, rbx                        ; its popups end
    mov rsi, r13
    call window_parent_gone
    mov rdi, rbx                        ; the keyboard on, while it is still
    mov rsi, r13                        ; among the others
    call stacking_unmapped
    mov rdi, rbx
    mov rsi, r13
    call input_forget_surface
    mov rdi, rbx
    mov rsi, r13
    call compositor_remove_surface
.done:
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12, r13, r14

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
    mov rdi, r12
    mov rsi, rax
    call surface_logical_size
    mov [r13 + Window.saved_w], eax
    mov [r13 + Window.saved_h], edx
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
    cmp dword [r13 + Window.decorated], 0
    je .go
    add ecx, TITLEBAR_H                 ; its bar inside the area too
    sub r9d, TITLEBAR_H
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
    mov r9, [rdi + Server.stack]        ; the layers on this output
.next:
    test r9, r9
    jz .done
    cmp [r9 + Surface.output], rsi
    jne .skip
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

; A toplevel to the output its middle is on, if that is another.
; rdi = server, rsi = surface
follow_output:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    mov rsi, [r12 + Surface.current + SurfaceState.buffer]
    test rsi, rsi
    jz .out
    mov rdi, [rbx + Server.buffer_table]
    call handle_resolve
    test rax, rax
    jz .out
    mov rdi, r12                        ; its middle, on the screen
    mov rsi, rax
    call surface_logical_size
    mov esi, eax
    shr esi, 1
    add esi, [r12 + Surface.current + SurfaceState.buf_x]
    shr edx, 1
    add edx, [r12 + Surface.current + SurfaceState.buf_y]
    mov rdi, rbx
    call compositor_output_at
    mov rdi, rbx
    mov rsi, r12
    mov rdx, rax
    call compositor_move_to_output
.out:
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12

; The surface where its Window says. r12 = surface, r13 = Window
put:
    mov eax, [r13 + Window.x]
    mov [r12 + Surface.current + SurfaceState.buf_x], eax
    mov eax, [r13 + Window.y]
    mov [r12 + Surface.current + SurfaceState.buf_y], eax
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
; output r8 as far as it goes, into Window.x / y of rsi; then each moved back
; towards the output's corner to a whole pixel of it (CMP-22: at 1.25 every
; 4 units, at 1.5 every 2), so the window's edges fall on pixels there
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
    call pixel_step
    cmp ecx, 1
    je .snapped
    mov eax, [rsi + Window.x]
    sub eax, [r8 + Output.x]
    xor edx, edx
    div ecx
    imul eax, ecx
    add eax, [r8 + Output.x]
    mov [rsi + Window.x], eax
    mov eax, [rsi + Window.y]
    sub eax, [r8 + Output.y]
    xor edx, edx
    div ecx
    imul eax, ecx
    add eax, [r8 + Output.y]
    mov [rsi + Window.y], eax
.snapped:
    ret

; Output r8 -> ecx = the fewest layout units that are a whole number of its
; pixels: 120 / gcd(scale in 120ths, 120); 1 at scale 1 or 2. eax, edx, r9
; are used.
pixel_step:
    mov ecx, 1
    mov rax, [r8 + Output.scale]
    test rax, rax
    jz .out
    imul rax, rax, 120                  ; 16.16 to 120ths, rounded
    add rax, 0x8000
    shr rax, 16
    test eax, eax
    jz .out
    mov ecx, eax                        ; gcd(it, 120)
    mov r9d, 120
.gcd:
    test r9d, r9d
    jz .have
    mov eax, ecx
    xor edx, edx
    div r9d
    mov ecx, r9d
    mov r9d, edx
    jmp .gcd
.have:
    mov eax, 120
    xor edx, edx
    div ecx
    mov ecx, eax
.out:
    ret

; Top-left at the pointer, kept on the output the pointer is on (with no
; seat, the middle of the window's output); a window with a title bar is
; placed with it, the bar on top.
; rdi = server, rsi = window, edx = width, ecx = height
place_at_pointer:
    mov r9, [rdi + Server.input_seat]
    test r9, r9
    jz .no_seat
    push rsi
    push rdx
    push rcx
    push rdi
    mov esi, [r9 + InputSeat.x]
    mov edx, [r9 + InputSeat.y]
    call compositor_output_at
    mov r8, rax
    pop rdi
    pop rcx
    pop rdx
    pop rsi
    test r8, r8
    jz .done
    mov r9, [rdi + Server.input_seat]
    mov eax, [r9 + InputSeat.x]
    mov r10d, [r9 + InputSeat.y]
    jmp .placed
.no_seat:
    OUTPUT_OF
    test r8, r8
    jz .done
.centre:
    mov eax, [r8 + Output.width]
    shr eax, 1
    add eax, [r8 + Output.x]
    mov r10d, [r8 + Output.height]
    shr r10d, 1
    add r10d, [r8 + Output.y]
.placed:
    cmp dword [rsi + Window.decorated], 0
    je keep_on_output
    add ecx, TITLEBAR_H
    call keep_on_output
    add dword [rsi + Window.y], TITLEBAR_H
.done:
    ret

; Centred on the toplevel it belongs to, kept on that one's output; a
; window with a title bar placed with it, the bar on top.
; rdi = server, rsi = window, edx = width, ecx = height
place_on_transient:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, 8                          ; 16-byte aligned
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov r14d, ecx
    cmp dword [r12 + Window.decorated], 0
    je .sized
    add r14d, TITLEBAR_H
.sized:
    mov r15, [r12 + Window.transient]
    mov rsi, [r15 + Surface.current + SurfaceState.buffer]
    mov rdi, [rbx + Server.buffer_table]
    call handle_resolve
    xor ecx, ecx                        ; the parent's size (0 without one)
    xor edx, edx
    test rax, rax
    jz .size
    mov rdi, r15
    mov rsi, rax
    call surface_logical_size
    mov ecx, eax
.size:
    mov eax, ecx                        ; x = its x + (its w - w) / 2
    sub eax, r13d
    sar eax, 1
    add eax, [r15 + Surface.current + SurfaceState.buf_x]
    mov r10d, edx                       ; y likewise
    sub r10d, r14d
    sar r10d, 1
    add r10d, [r15 + Surface.current + SurfaceState.buf_y]
    mov r8, [r15 + Surface.output]
    mov rsi, r12
    mov edx, r13d
    mov ecx, r14d
    call keep_on_output
    cmp dword [r12 + Window.decorated], 0
    je .out
    add dword [r12 + Window.y], TITLEBAR_H
.out:
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15

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
