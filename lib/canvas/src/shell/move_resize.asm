; ============================================================================
; Move/Resize — Interactive Window Move and Resize
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

section .text

struc MoveResize {
    .seat:              resq 1
    .toplevel:          resq 1
    .type:              resd 1
    .edges:             resd 1
    .start_x:           resd 1
    .start_y:           resd 1
    .initial_x:         resd 1
    .initial_y:         resd 1
    .initial_width:     resd 1
    .initial_height:    resd 1
    .min_width:         resd 1
    .min_height:        resd 1
    .max_width:         resd 1
    .max_height:        resd 1
    .grab:              resq 1
}
%define MoveResize_size    104

%define MOVE_RESIZE_MOVE      0
%define MOVE_RESIZE_RESIZE    1

%define RESIZE_EDGE_NONE      0
%define RESIZE_EDGE_TOP       (1 << 0)
%define RESIZE_EDGE_BOTTOM    (1 << 1)
%define RESIZE_EDGE_LEFT      (1 << 2)
%define RESIZE_EDGE_RIGHT     (1 << 3)
%define RESIZE_EDGE_TOP_LEFT      (RESIZE_EDGE_TOP | RESIZE_EDGE_LEFT)
%define RESIZE_EDGE_TOP_RIGHT     (RESIZE_EDGE_TOP | RESIZE_EDGE_RIGHT)
%define RESIZE_EDGE_BOTTOM_LEFT   (RESIZE_EDGE_BOTTOM | RESIZE_EDGE_LEFT)
%define RESIZE_EDGE_BOTTOM_RIGHT  (RESIZE_EDGE_BOTTOM | RESIZE_EDGE_RIGHT)

; ---------------------------------------------------------------------------
; move_resize_init
; ---------------------------------------------------------------------------
global move_resize_init
move_resize_init:
    PROLOGUE
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; move_resize_start
;   Start interactive move or resize
; ---------------------------------------------------------------------------
global move_resize_start
move_resize_start:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov r14d, ecx
    mov r15d, r8d
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Allocate move/resize
    mov rdi, [rbx + Server.arena]
    mov rsi, MoveResize_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax

    ; Initialize
    mov qword [rbx + MoveResize.seat], r12
    mov qword [rbx + MoveResize.toplevel], r13
    mov dword [rbx + MoveResize.type], r13d
    mov dword [rbx + MoveResize.edges], r14d
    mov eax, [r12 + Pointer.x]
    mov [rbx + MoveResize.start_x], eax
    mov eax, [r12 + Pointer.y]
    mov [rbx + MoveResize.start_y], eax

    mov rax, [r13 + Toplevel.surface]
    mov eax, [rax + Surface.current + SurfaceState.buf_x]
    mov [rbx + MoveResize.initial_x], eax
    mov eax, [rax + Surface.current + SurfaceState.buf_y]
    mov [rbx + MoveResize.initial_y], eax
    mov eax, [rax + Surface.current + SurfaceState.width]
    mov [rbx + MoveResize.initial_width], eax
    mov eax, [rax + Surface.current + SurfaceState.height]
    mov [rbx + MoveResize.initial_height], eax

    ; Get constraints
    mov eax, [r13 + Toplevel.min_width]
    mov [rbx + MoveResize.min_width], eax
    mov eax, [r13 + Toplevel.min_height]
    mov [rbx + MoveResize.min_height], eax
    mov eax, [r13 + Toplevel.max_width]
    mov [rbx + MoveResize.max_width], eax
    mov eax, [r13 + Toplevel.max_height]
    mov [rbx + MoveResize.max_height], eax

    ; Grab pointer
    mov rdi, [r13 + Toplevel.shell]
    mov rsi, GRAB_POINTER
    mov rdx, rbx
    mov rcx, 0
    call grab_pointer
    test rax, rax
    jnz .grab_fail
    mov qword [rbx + MoveResize.grab], rax

    ; Add to seat's move/resize list
    mov rax, [r12 + Seat.move_resize]
    mov [rbx + MoveResize.next], rax
    mov [r12 + Seat.move_resize], rbx

    xor rax, rax
    ret

.oom:
    RETURN_ERROR ENOMEM
.grab_fail:
    RETURN_ERROR EBUSY

; ---------------------------------------------------------------------------
; move_resize_update
;   Update move/resize with new pointer position
; ---------------------------------------------------------------------------
global move_resize_update
move_resize_update:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    ASSERT_PTR rbx

    ; Calculate delta
    mov eax, [rbx + MoveResize.start_x]
    sub r12d, eax
    mov eax, [rbx + MoveResize.start_y]
    sub r13d, eax

    cmp dword [rbx + MoveResize.type], MOVE_RESIZE_MOVE
    je .do_move

    ; Resize
    mov eax, [rbx + MoveResize.edges]
    test eax, RESIZE_EDGE_LEFT
    jz .check_right
    ; Left edge: move left edge, adjust width
    mov eax, [rbx + MoveResize.initial_width]
    sub eax, r12d
    cmp eax, [rbx + MoveResize.min_width]
    cmovl eax, [rbx + MoveResize.min_width]
    cmp eax, [rbx + MoveResize.max_width]
    cmovg eax, [rbx + MoveResize.max_width]
    mov [rbx + MoveResize.initial_width], eax
    mov eax, [rbx + MoveResize.initial_x]
    add eax, r12d
    mov [rbx + MoveResize.initial_x], eax

.check_right:
    test eax, RESIZE_EDGE_RIGHT
    jz .check_top
    mov eax, [rbx + MoveResize.initial_width]
    add eax, r12d
    cmp eax, [rbx + MoveResize.min_width]
    cmovl eax, [rbx + MoveResize.min_width]
    cmp eax, [rbx + MoveResize.max_width]
    cmovg eax, [rbx + MoveResize.max_width]
    mov [rbx + MoveResize.initial_width], eax

.check_top:
    test eax, RESIZE_EDGE_TOP
    jz .check_bottom
    mov eax, [rbx + MoveResize.initial_height]
    sub eax, r13d
    cmp eax, [rbx + MoveResize.min_height]
    cmovl eax, [rbx + MoveResize.min_height]
    cmp eax, [rbx + MoveResize.max_height]
    cmovg eax, [rbx + MoveResize.max_height]
    mov [rbx + MoveResize.initial_height], eax
    mov eax, [rbx + MoveResize.initial_y]
    add eax, r13d
    mov [rbx + MoveResize.initial_y], eax

.check_bottom:
    test eax, RESIZE_EDGE_BOTTOM
    jz .apply
    mov eax, [rbx + MoveResize.initial_height]
    add eax, r13d
    cmp eax, [rbx + MoveResize.min_height]
    cmovl eax, [rbx + MoveResize.min_height]
    cmp eax, [rbx + MoveResize.max_height]
    cmovg eax, [rbx + MoveResize.max_height]
    mov [rbx + MoveResize.initial_height], eax

.apply:
    ; Apply to surface pending state
    mov r14, [rbx + MoveResize.toplevel]
    mov rax, [r14 + Toplevel.surface]
    mov r15, [rax + Surface.pending]

    mov eax, [rbx + MoveResize.initial_x]
    mov [r15 + SurfaceState.buf_x], eax
    mov eax, [rbx + MoveResize.initial_y]
    mov [r15 + SurfaceState.buf_y], eax
    mov eax, [rbx + MoveResize.initial_width]
    mov [r15 + SurfaceState.width], eax
    mov eax, [rbx + MoveResize.initial_height]
    mov [r15 + SurfaceState.height], eax
    mov byte [r15 + SurfaceState.pending], 1

    ; Schedule configure
    call toplevel_schedule_configure
    ret

.do_move:
    ; Move: update position
    mov r14, [rbx + MoveResize.toplevel]
    mov rax, [r14 + Toplevel.surface]
    mov r15, [rax + Surface.pending]

    mov eax, [rbx + MoveResize.initial_x]
    add eax, r12d
    mov [r15 + SurfaceState.buf_x], eax

    mov eax, [rbx + MoveResize.initial_y]
    add eax, r13d
    mov [r15 + SurfaceState.buf_y], eax

    mov byte [r15 + SurfaceState.pending], 1

    call toplevel_schedule_configure
    ret

.oom:
    RETURN_ERROR ENOMEM

; ---------------------------------------------------------------------------
; move_resize_end
;   End move/resize
; ---------------------------------------------------------------------------
global move_resize_end
move_resize_end:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Release grab
    mov rax, [rbx + MoveResize.grab]
    test rax, rax
    jz .no_grab
    mov rdi, [rbx + MoveResize.seat]
    mov rsi, rax
    call grab_release

.no_grab:
    ; Remove from seat list
    ; TODO

    ; Commit final state
    mov rax, [rbx + MoveResize.toplevel]
    call toplevel_schedule_configure

    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; move_resize_cancel
; ---------------------------------------------------------------------------
global move_resize_cancel
move_resize_cancel:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Release grab
    mov rax, [rbx + MoveResize.grab]
    test rax, rax
    jz .no_grab
    mov rdi, [rbx + MoveResize.seat]
    mov rsi, rax
    call grab_release

.no_grab:
    ; Restore initial geometry
    mov rax, [rbx + MoveResize.toplevel]
    mov r14, [rax + Toplevel.surface]
    mov r15, [r14 + Surface.pending]

    mov eax, [rbx + MoveResize.initial_x]
    mov [r15 + SurfaceState.buf_x], eax
    mov eax, [rbx + MoveResize.initial_y]
    mov [r15 + SurfaceState.buf_y], eax
    mov eax, [rbx + MoveResize.initial_width]
    mov [r15 + SurfaceState.width], eax
    mov eax, [rbx + MoveResize.initial_height]
    mov [r15 + SurfaceState.height], eax
    mov byte [r15 + SurfaceState.pending], 1

    call toplevel_schedule_configure

    call move_resize_end
    ret

section .data
global move_resize_version
move_resize_version: dq 0x010000