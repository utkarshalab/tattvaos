; ============================================================================
; Drag and Drop (cw_dnd)
; ============================================================================
; A drag offers its data as cw_clipboard selection CLIP_DRAG, so the data
; moves as a paste does (data/clipboard.asm). dnd_start begins one while a
; button is held on the client's own surface, the one the pointer holds.
; While it lasts the pointer's motion is the drag's (input calls dnd_over):
; the surface under the pointer hears enter, after the offer as
; cw_clipboard.offered, then motion, and leave when the pointer goes on.
; Letting go of the last button (dnd_release) drops on the surface under the
; pointer, whose client may then paste selection CLIP_DRAG, and tells the one
; dragging finished(1); over no surface, finished(0). The state is in
; ClipboardState.
;
; Actions (copy, move) are offered by the one dragging (dnd_set_actions; copy
; if it says nothing) and told in enter; the one under the pointer accepts one
; (dnd_accept), and only an accepted drop drops: drop and finished carry the
; action, copy over move when both were. An icon (dnd_set_icon), one of the
; dragging client's surfaces, comes off the stack and is drawn at the pointer
; (dnd_render_icon, over everything but the cursor) until the drag ends.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/cwp.inc"
%include "inc/cwp_ops.inc"
%include "inc/struct_offsets.inc"

extern clipboard_take
extern compositor_add_surface
extern compositor_damage_rect
extern compositor_remove_surface
extern handle_resolve
extern surface_logical_size
extern sw_render_surface
extern clipboard_tell
extern sync_event

section .text

; ---------------------------------------------------------------------------
; dnd_start
;   start(surface, count, types): a drag from the client's surface
;   IN:  rdi = server*, rsi = client*, rdx = Surface* (its own), rcx = the
;        payload (count at 4, types at 8)
;   OUT: rax = 0, -EINVAL, -EPERM unless a button is held on that surface
; ---------------------------------------------------------------------------
global dnd_start
dnd_start:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov rax, -(EINVAL)
    cmp qword [rbx + Server.clipboard], 0
    je .out
    cmp dword [r14 + 4], CLIP_TYPES
    ja .out
    mov rax, -(EPERM)                   ; the pointer held on it
    mov rcx, [rbx + Server.input_seat]
    test rcx, rcx
    jz .out
    cmp dword [rcx + InputSeat.buttons], 0
    je .out
    cmp [rcx + InputSeat.pointer_focus], r13
    jne .out
    mov rdi, rbx
    call end_drag                       ; one at a time
    mov rdi, rbx
    mov rsi, r12
    mov edx, CLIP_DRAG
    mov ecx, [r14 + 4]
    lea r8, [r14 + 8]
    call clipboard_take
    mov rax, [rbx + Server.clipboard]
    mov dword [rax + ClipboardState.dragging], 1
    mov [rax + ClipboardState.drag_source], r13
    mov qword [rax + ClipboardState.drag_over], 0
    mov qword [rax + ClipboardState.drop_target], 0
    mov dword [rax + ClipboardState.drag_actions], DND_COPY
    mov dword [rax + ClipboardState.drag_accepted], 0
    mov qword [rax + ClipboardState.drag_icon], 0
    xor eax, eax
.out:
    EPILOGUE_RESTORE rbx, r12, r13, r14

; ---------------------------------------------------------------------------
; dnd_set_actions
;   The one dragging: the actions it allows (copy 1, move 2; none is copy)
;   IN:  rdi = server*, rsi = client*, edx = actions
;   OUT: rax = 0, -EPERM unless its drag is under way
; ---------------------------------------------------------------------------
global dnd_set_actions
dnd_set_actions:
    call dragging_from
    test rax, rax
    js .out
    and edx, DND_COPY | DND_MOVE
    jnz .some
    mov edx, DND_COPY
.some:
    mov [rax + ClipboardState.drag_actions], edx
    and [rax + ClipboardState.drag_accepted], edx
    xor eax, eax
.out:
    ret

; ---------------------------------------------------------------------------
; dnd_accept
;   The one under the pointer: the action it would take (0: none), one of
;   those offered
;   IN:  rdi = server*, rsi = client*, edx = action
;   OUT: rax = 0, -EPERM unless a drag is over its surface
; ---------------------------------------------------------------------------
global dnd_accept
dnd_accept:
    mov rax, -(EPERM)
    mov rcx, [rdi + Server.clipboard]
    test rcx, rcx
    jz .out
    cmp dword [rcx + ClipboardState.dragging], 0
    je .out
    mov r8, [rcx + ClipboardState.drag_over]
    test r8, r8
    jz .out
    cmp [r8 + Surface.client], rsi
    jne .out
    and edx, [rcx + ClipboardState.drag_actions]
    mov [rcx + ClipboardState.drag_accepted], edx
    xor eax, eax
.out:
    ret

; ---------------------------------------------------------------------------
; dnd_set_icon
;   The one dragging: its surface drawn at the pointer while the drag lasts
;   IN:  rdi = server*, rsi = client*, rdx = Surface* (its own)
;   OUT: rax = 0, -EPERM unless its drag is under way
; ---------------------------------------------------------------------------
global dnd_set_icon
dnd_set_icon:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rdx
    call dragging_from
    test rax, rax
    js .out
    cmp qword [rax + ClipboardState.drag_icon], 0
    je .new
    mov rdi, rbx                        ; another one before: back
    call icon_back
.new:
    mov rdi, rbx                        ; off the stack, then at the pointer
    mov rsi, r12
    call compositor_remove_surface
    mov rax, [rbx + Server.clipboard]
    mov [rax + ClipboardState.drag_icon], r12
    mov rdi, rbx
    call icon_follow
    xor eax, eax
.out:
    EPILOGUE_RESTORE rbx, r12

; ---------------------------------------------------------------------------
; dnd_render_icon
;   The drag's icon, the part inside the clip
;   IN:  rdi = frame context, rsi = clip rect*, rdx = server*
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global dnd_render_icon
dnd_render_icon:
    mov rax, [rdx + Server.clipboard]
    test rax, rax
    jz .none
    cmp dword [rax + ClipboardState.dragging], 0
    je .none
    mov rax, [rax + ClipboardState.drag_icon]
    test rax, rax
    jz .none
    mov rdx, rsi
    mov rsi, rax
    jmp sw_render_surface
.none:
    xor eax, eax
    ret

; ---------------------------------------------------------------------------
; dnd_active
;   IN:  rdi = server*  OUT: eax = 1 while a drag is under way
; ---------------------------------------------------------------------------
global dnd_active
dnd_active:
    xor eax, eax
    mov rcx, [rdi + Server.clipboard]
    test rcx, rcx
    jz .out
    mov eax, [rcx + ClipboardState.dragging]
.out:
    ret

; ---------------------------------------------------------------------------
; dnd_over
;   The pointer moved during a drag: over this surface now (0: none)
;   IN:  rdi = server*, rsi = Surface* under the pointer, 0 for none
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global dnd_over
dnd_over:
    PROLOGUE_SAVE rbx, r12, r13
    sub rsp, 8                          ; 16-byte aligned
    mov rbx, rdi
    mov r12, rsi
    mov r13, [rbx + Server.clipboard]
    mov rdi, rbx                        ; the icon with the pointer
    call icon_follow
    mov rax, [r13 + ClipboardState.drag_over]
    cmp rax, r12
    jne .changed
    test r12, r12
    jz .done
    mov rdi, rbx                        ; the same one: motion
    mov rsi, r12
    mov edx, DND_EV_MOTION
    call send_at
    jmp .done
.changed:
    test rax, rax
    jz .enter
    mov rdi, rbx                        ; the last one: leave
    mov rsi, rax
    call send_leave
.enter:
    mov [r13 + ClipboardState.drag_over], r12
    mov dword [r13 + ClipboardState.drag_accepted], 0   ; its own to accept
    test r12, r12
    jz .done
    mov rdi, rbx                        ; this one: what is offered, enter
    mov rsi, [r12 + Surface.client]
    mov edx, CLIP_DRAG
    call clipboard_tell
    mov rdi, rbx
    mov rsi, r12
    mov edx, DND_EV_ENTER
    mov ecx, [r13 + ClipboardState.drag_actions]
    call send_at
.done:
    xor eax, eax
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13

; ---------------------------------------------------------------------------
; dnd_release
;   The last button let go: a drag drops on the surface under the pointer,
;   or over none ends; the one dragging hears which
;   IN:  rdi = server*
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global dnd_release
dnd_release:
    PROLOGUE_SAVE rbx, r12
    sub rsp, 16                         ; finished's payload; aligned
    mov rbx, rdi
    mov r12, [rbx + Server.clipboard]
    test r12, r12
    jz .done
    cmp dword [r12 + ClipboardState.dragging], 0
    je .done
    mov qword [rsp], 0                  ; dropped? the action
    mov rsi, [r12 + ClipboardState.drag_over]
    test rsi, rsi
    jz .finish
    mov ecx, [r12 + ClipboardState.drag_accepted]
    test ecx, ecx
    jnz .accepted
    mov rdi, rbx                        ; not taken there: left, not dropped
    call send_leave
    jmp .finish
.accepted:
    mov eax, DND_COPY                   ; copy over move when both
    test ecx, eax
    jnz .action
    mov eax, DND_MOVE
.action:
    mov [rsp + 4], eax
    mov rax, [rsi + Surface.client]     ; its client may paste
    mov [r12 + ClipboardState.drop_target], rax
    mov rdi, rbx
    mov edx, DND_EV_DROP
    mov ecx, [rsp + 4]
    call send_at
    mov dword [rsp], 1
.finish:
    mov rdi, rbx                        ; the icon back where it was
    call icon_back
    mov rax, [r12 + ClipboardState.drag_source]
    mov rdi, [rax + Surface.client]
    mov esi, CWP_OBJ_DND
    mov edx, DND_EV_FINISHED
    mov rcx, rsp
    mov r8d, 8
    call sync_event
    mov dword [r12 + ClipboardState.dragging], 0
    mov qword [r12 + ClipboardState.drag_over], 0
    mov qword [r12 + ClipboardState.drag_source], 0
.done:
    xor eax, eax
    add rsp, 16
    EPILOGUE_RESTORE rbx, r12

; ---------------------------------------------------------------------------
; dnd_forget_surface
;   A surface going: no longer under the drag; the drag it started ends
;   IN:  rdi = server*, rsi = Surface*
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global dnd_forget_surface
dnd_forget_surface:
    mov rax, [rdi + Server.clipboard]
    test rax, rax
    jz .done
    cmp [rax + ClipboardState.drag_icon], rsi
    jne .over
    mov qword [rax + ClipboardState.drag_icon], 0   ; gone, not put back
.over:
    cmp [rax + ClipboardState.drag_over], rsi
    jne .source
    mov qword [rax + ClipboardState.drag_over], 0
.source:
    cmp [rax + ClipboardState.drag_source], rsi
    jne .done
    mov dword [rax + ClipboardState.dragging], 0
    mov qword [rax + ClipboardState.drag_source], 0
    mov rsi, [rax + ClipboardState.drag_over]
    mov qword [rax + ClipboardState.drag_over], 0
    test rsi, rsi
    jz .done
    jmp send_leave                      ; rdi = server, rsi = the one under it
.done:
    xor eax, eax
    ret

; ---------------------------------------------------------------------------
; Local
; ---------------------------------------------------------------------------

; rdi = server: a drag under way ends, its icon put back, the surface under
; it told leave
end_drag:
    mov rax, [rdi + Server.clipboard]
    cmp dword [rax + ClipboardState.dragging], 0
    je .done
    push rdi
    call icon_back
    pop rdi
    mov rax, [rdi + Server.clipboard]
    mov dword [rax + ClipboardState.dragging], 0
    mov qword [rax + ClipboardState.drag_source], 0
    mov rsi, [rax + ClipboardState.drag_over]
    mov qword [rax + ClipboardState.drag_over], 0
    test rsi, rsi
    jnz send_leave
.done:
    xor eax, eax
    ret

; rdi = server, rsi = client -> rax = ClipboardState if that client's drag
; is under way, else -EPERM; rdx kept
dragging_from:
    mov rax, [rdi + Server.clipboard]
    test rax, rax
    jz .no
    cmp dword [rax + ClipboardState.dragging], 0
    je .no
    mov rcx, [rax + ClipboardState.drag_source]
    cmp [rcx + Surface.client], rsi
    jne .no
    ret
.no:
    mov rax, -(EPERM)
    ret

; rdi = server: the icon, if there is one, redrawn where it was and moved
; to the pointer and redrawn there
icon_follow:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov rax, [rbx + Server.clipboard]
    mov r12, [rax + ClipboardState.drag_icon]
    test r12, r12
    jz .done
    mov rdi, rbx
    call icon_damage
    mov rax, [rbx + Server.input_seat]
    mov ecx, [rax + InputSeat.x]
    add ecx, DND_ICON_OFFSET
    mov [r12 + Surface.current + SurfaceState.buf_x], ecx
    mov ecx, [rax + InputSeat.y]
    add ecx, DND_ICON_OFFSET
    mov [r12 + Surface.current + SurfaceState.buf_y], ecx
    mov rdi, rbx
    call icon_damage
.done:
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12

; rdi = server: the icon goes back on the stack, redrawn, the drag without
; one
icon_back:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov rax, [rbx + Server.clipboard]
    mov r12, [rax + ClipboardState.drag_icon]
    test r12, r12
    jz .done
    mov rdi, rbx
    call icon_damage
    mov rax, [rbx + Server.clipboard]
    mov qword [rax + ClipboardState.drag_icon], 0
    mov rdi, [rbx + Server.outputs]
    test rdi, rdi
    jz .done
    mov rsi, r12
    call compositor_add_surface
.done:
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12

; rdi = server: where the icon is, redrawn (it is off the stack, so this is
; done here rather than by compositor_damage_surface)
icon_damage:
    PROLOGUE_SAVE rbx, r12
    sub rsp, 16                         ; a rect; 16-byte aligned
    mov rbx, rdi
    mov rax, [rbx + Server.clipboard]
    mov r12, [rax + ClipboardState.drag_icon]
    mov rsi, [r12 + Surface.current + SurfaceState.buffer]
    test rsi, rsi
    jz .done
    mov rdi, [rbx + Server.buffer_table]
    call handle_resolve
    test rax, rax
    jz .done
    mov rdi, r12
    mov rsi, rax
    call surface_logical_size
    mov [rsp + 8], eax
    mov [rsp + 12], edx
    mov eax, [r12 + Surface.current + SurfaceState.buf_x]
    mov [rsp], eax
    mov eax, [r12 + Surface.current + SurfaceState.buf_y]
    mov [rsp + 4], eax
    mov rdi, rbx
    mov rsi, rsp
    call compositor_damage_rect
.done:
    xor eax, eax
    add rsp, 16
    EPILOGUE_RESTORE rbx, r12

; rdi = server, rsi = surface, edx = DND_EV_*, ecx = a fourth value (enter's
; actions, drop's action): (surface, x, y, it) to its client, the pointer in
; the surface's own pixels
send_at:
    sub rsp, 24
    mov [rsp + 12], ecx
    mov eax, [rsi + Surface.id]
    mov [rsp], eax
    mov rax, [rdi + Server.input_seat]
    mov ecx, [rax + InputSeat.x]
    sub ecx, [rsi + Surface.current + SurfaceState.buf_x]
    mov [rsp + 4], ecx
    mov ecx, [rax + InputSeat.y]
    sub ecx, [rsi + Surface.current + SurfaceState.buf_y]
    mov [rsp + 8], ecx
    mov rdi, [rsi + Surface.client]
    mov esi, CWP_OBJ_DND
    mov rcx, rsp
    mov r8d, 12                         ; motion: three values
    cmp edx, DND_EV_MOTION
    je .sized
    mov r8d, 16                         ; enter, drop: four
.sized:
    call sync_event
    add rsp, 24
    ret

; rdi = server, rsi = surface: leave(surface) to its client
send_leave:
    sub rsp, 24
    mov eax, [rsi + Surface.id]
    mov [rsp], eax
    mov rdi, [rsi + Surface.client]
    mov esi, CWP_OBJ_DND
    mov edx, DND_EV_LEAVE
    mov rcx, rsp
    mov r8d, 4
    call sync_event
    add rsp, 24
    ret

section .data
global dnd_version
dnd_version: dq 0x020000
