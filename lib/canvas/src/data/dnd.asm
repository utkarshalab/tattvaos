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

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/cwp.inc"
%include "inc/cwp_ops.inc"
%include "inc/struct_offsets.inc"

extern clipboard_take
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
    xor eax, eax
.out:
    EPILOGUE_RESTORE rbx, r12, r13, r14

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
    test r12, r12
    jz .done
    mov rdi, rbx                        ; this one: what is offered, enter
    mov rsi, [r12 + Surface.client]
    mov edx, CLIP_DRAG
    call clipboard_tell
    mov rdi, rbx
    mov rsi, r12
    mov edx, DND_EV_ENTER
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
    mov dword [rsp], 0                  ; dropped?
    mov rsi, [r12 + ClipboardState.drag_over]
    test rsi, rsi
    jz .finish
    mov rax, [rsi + Surface.client]     ; its client may paste
    mov [r12 + ClipboardState.drop_target], rax
    mov rdi, rbx
    mov edx, DND_EV_DROP
    call send_at
    mov dword [rsp], 1
.finish:
    mov rax, [r12 + ClipboardState.drag_source]
    mov rdi, [rax + Surface.client]
    mov esi, CWP_OBJ_DND
    mov edx, DND_EV_FINISHED
    mov rcx, rsp
    mov r8d, 4
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

; rdi = server: a drag under way ends, the surface under it told leave
end_drag:
    mov rax, [rdi + Server.clipboard]
    cmp dword [rax + ClipboardState.dragging], 0
    je .done
    mov dword [rax + ClipboardState.dragging], 0
    mov qword [rax + ClipboardState.drag_source], 0
    mov rsi, [rax + ClipboardState.drag_over]
    mov qword [rax + ClipboardState.drag_over], 0
    test rsi, rsi
    jnz send_leave
.done:
    xor eax, eax
    ret

; rdi = server, rsi = surface, edx = DND_EV_*: (surface, x, y) to its
; client, the pointer in the surface's own pixels
send_at:
    sub rsp, 24
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
    mov r8d, 12
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
