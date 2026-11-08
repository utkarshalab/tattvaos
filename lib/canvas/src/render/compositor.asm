; ============================================================================
; Compositor — Damage-Driven Composition Driver
; Coordinates renderer, damage tracking, frame scheduling
; ============================================================================
; Every surface shown is on one stack, Server.stack, bottom to top, linked by
; z_order_next / z_order_prev, in stacking levels (LEVEL_* in
; inc/struct_offsets.inc; a surface's is its shell role's, LEVEL_NORMAL with
; none). A surface goes in, or is raised, to the top of its own level.
;
; Positions are in the layout's coordinates, every output a part of it at
; Output.x, Output.y; each output's damage too. Each output draws every
; surface over its part, so a window over an edge shows on both; damage goes
; to every output it touches. Surface.output is a surface's own output, for
; placing it, and 0 while it is off the screen.
;
; An output that mirrors another (Output.mirror_of) is not drawn itself: once
; its source is, the source's damaged pixels are scaled into it
; (mirror_copy, bilinear, the whole source over the whole mirror).
; It gets no damage of its own, and is no part of the layout:
; compositor_output_at and compositor_layout_bounds pass it by, so nothing
; is placed on it and the pointer is not kept on it.
;
; While the screen is locked (Server.locked) only overlays are drawn, the
; login screen among them: on every output, everything else is background.
;
; Each damaged rectangle is drawn from the topmost surface that is opaque
; over all of it, up: what is under it, the background too, cannot show and
; is not drawn. A buffer without alpha is opaque everywhere; otherwise the
; surface's opaque region says, one of its rectangles holding the whole
; damaged one (a looser test could draw too little). A frame moves each surface's committed damage
; to the output, redraws every damaged rectangle from the background up, then
; tells the surfaces their frame is done. Nothing damaged means no frame.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/render.inc"
%include "inc/color.inc"
%include "inc/backend.inc"
%include "inc/struct_offsets.inc"
%include "ugfx.inc"

extern output_present
extern arena_alloc
extern frame_clock_schedule
extern handle_resolve
extern presentation_complete
extern rect_intersect
extern region_add_rect
extern scale_bilinear_rect
extern sw_cursor_render
extern surface_logical_size
extern magnify_frame
extern magnify_output
extern dnd_render_icon
extern region_clear
extern region_is_empty
extern surface_fire_frame_callbacks
extern sw_render_init
extern sw_render_begin_frame
extern sw_render_rect
extern sw_render_surface
extern sw_render_end_frame
extern titlebar_rect
extern titlebar_render
extern switcher_render

%define COMPOSITOR_BG_COLOR COMPOSITOR_BG  ; inc/struct_offsets.inc

; %1 = Output* register -> %2 = the address of the server's stack head
%macro STACK_OF 2
    mov %2, [%1 + Output.backend]
    mov %2, [%2 + Backend.server]
    lea %2, [%2 + Server.stack]
%endmacro

; %1 = Surface* register -> %2 = its stacking level (32-bit register); uses r10
%macro LEVEL_OF 2
    xor %2, %2
    mov r10, [%1 + Surface.window]
    test r10, r10
    jz %%done
    mov %2, [r10 + Window.level]
%%done:
%endmacro

; %1 = Server* register, %2 = Surface* register: to %3 if the lock hides
; the surface (locked, and it is below the overlays); uses r10
%macro LOCK_HIDES 3
    cmp qword [%1 + Server.locked], 0
    je %%shown
    mov r10, [%2 + Surface.window]
    test r10, r10
    jz %3
    cmp dword [r10 + Window.level], LEVEL_OVERLAY
    jl %3
%%shown:
%endmacro

section .text

; ---------------------------------------------------------------------------
; compositor_init
;   Initialize compositor
;   IN:  rdi = compositor*, rsi = server*, rdx = arena
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global compositor_init
compositor_init:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13

    mov qword [rbx + Compositor.server], r12
    mov rdi, r13
    mov rsi, Renderer_size
    call arena_alloc
    test rax, rax
    jz .init_oom
    mov qword [rbx + Compositor.renderer], rax
    mov qword [rbx + Compositor.arena], r13
    mov qword [rbx + Compositor.damage_ring], 0
    mov qword [rbx + Compositor.frame_seq], 0
    mov dword [rbx + Compositor.bg_color], COMPOSITOR_BG_COLOR

    ; Initialize software renderer
    mov rdi, [rbx + Compositor.renderer]
    mov rsi, [r12 + Server.backend]
    mov rdx, r13
    call sw_render_init

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.init_oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; compositor_deinit
; ---------------------------------------------------------------------------
global compositor_deinit
compositor_deinit:
    xor eax, eax
    ret

; ---------------------------------------------------------------------------
; compositor_add_surface
;   Show a surface, its own output that one: on the stack above everything
;   at its level or below
;   IN:  rdi = output*, rsi = surface*
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global compositor_add_surface
compositor_add_surface:
    ASSERT_PTR rdi
    ASSERT_PTR rsi
    mov [rsi + Surface.output], rdi
    STACK_OF rdi, r11
    LEVEL_OF rsi, r8d
    xor ecx, ecx                        ; the one it goes above; 0: the bottom
    mov rax, [r11]
.walk:
    test rax, rax
    jz .insert
    LEVEL_OF rax, r9d
    cmp r9d, r8d
    jg .insert                          ; a higher level starts here
    mov rcx, rax
    mov rax, [rax + Surface.z_order_next]
    jmp .walk
.insert:
    mov [rsi + Surface.z_order_prev], rcx
    mov [rsi + Surface.z_order_next], rax
    test rax, rax
    jz .linked_above
    mov [rax + Surface.z_order_prev], rsi
.linked_above:
    test rcx, rcx
    jz .bottom
    mov [rcx + Surface.z_order_next], rsi
    jmp .done
.bottom:
    mov [r11], rsi
.done:
    xor eax, eax
    ret

; ---------------------------------------------------------------------------
; compositor_damage_surface
;   What a surface shows needs redrawing, on every output it is over
;   IN:  rdi = server*, rsi = surface*
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global compositor_damage_surface
compositor_damage_surface:
    PROLOGUE_SAVE rbx, r12, r13
    sub rsp, 24                         ; a rect; 16-byte aligned
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov r13, [r12 + Surface.output]
    test r13, r13
    jz .done
    mov rsi, [r12 + Surface.current + SurfaceState.buffer]
    test rsi, rsi
    jz .done                            ; showing nothing
    mov rdi, [rbx + Server.buffer_table]
    call handle_resolve
    test rax, rax
    jz .done
    mov ecx, [r12 + Surface.current + SurfaceState.buf_x]
    mov [rsp], ecx
    mov ecx, [r12 + Surface.current + SurfaceState.buf_y]
    mov [rsp + 4], ecx
    mov rdi, r12                        ; its size on the screen
    mov rsi, rax
    call surface_logical_size
    mov [rsp + 8], eax
    mov [rsp + 12], edx
    mov rdi, rbx
    mov rsi, rsp
    call compositor_damage_rect
    mov rdi, r12                        ; and its title bar, if it has one
    mov rsi, rsp
    call titlebar_rect
    test eax, eax
    jz .done
    mov rdi, rbx
    mov rsi, rsp
    call compositor_damage_rect
.done:
    xor eax, eax
    add rsp, 24
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; compositor_raise_surface
;   Put a surface above everything else at its level
;   IN:  rdi = server*, rsi = surface*
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global compositor_raise_surface
compositor_raise_surface:
    PROLOGUE_SAVE rbx, r12, r13
    sub rsp, 8                          ; 16-byte aligned
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov r13, [r12 + Surface.output]
    test r13, r13
    jz .done
    mov rcx, [r12 + Surface.z_order_next]
    test rcx, rcx
    jz .done                            ; on top already
    LEVEL_OF r12, r8d
    LEVEL_OF rcx, r9d
    cmp r9d, r8d
    jg .done                            ; on top of its level already
    mov rax, [r12 + Surface.z_order_prev]
    mov [rcx + Surface.z_order_prev], rax
    test rax, rax
    jz .was_bottom
    mov [rax + Surface.z_order_next], rcx
    jmp .relink
.was_bottom:
    mov [rbx + Server.stack], rcx
.relink:
    mov rdi, r13
    mov rsi, r12
    call compositor_add_surface
    mov rdi, rbx                        ; it now covers what it did not
    mov rsi, r12
    call compositor_damage_surface
.done:
    xor eax, eax
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; compositor_move_to_output
;   A surface's own output is another now (the one its middle is on); it is
;   redrawn where it is
;   IN:  rdi = server*, rsi = surface*, rdx = Output*
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global compositor_move_to_output
compositor_move_to_output:
    PROLOGUE_SAVE rbx, r12, r13
    sub rsp, 8                          ; 16-byte aligned
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    test r13, r13
    jz .done
    mov rax, [r12 + Surface.output]
    test rax, rax
    jz .done                            ; off the screen: stays off
    cmp rax, r13
    je .done
    mov [r12 + Surface.output], r13     ; its place on the stack is the same
    mov rdi, rbx
    mov rsi, r12
    call compositor_damage_surface
.done:
    xor eax, eax
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13

; ---------------------------------------------------------------------------
; compositor_output_at
;   The output a point of the layout is on, else the nearest one along the
;   row of outputs (the first, if there is just one); never a mirror
;   IN:  rdi = server*, esi = x, edx = y
;   OUT: rax = Output*, 0 with none
; ---------------------------------------------------------------------------
global compositor_output_at
compositor_output_at:
    mov rax, [rdi + Server.outputs]
    xor r8d, r8d                        ; the fallback: the first
.next:
    test rax, rax
    jz .fallback
    cmp qword [rax + Output.mirror_of], 0
    jne .skip
    test r8, r8
    jnz .have_first
    mov r8, rax
.have_first:
    mov ecx, [rax + Output.x]
    cmp esi, ecx
    jl .skip
    add ecx, [rax + Output.width]
    cmp esi, ecx
    jge .right_of
    mov ecx, [rax + Output.y]
    cmp edx, ecx
    jl .skip
    add ecx, [rax + Output.height]
    cmp edx, ecx
    jl .found
    jmp .skip
.right_of:
    mov r8, rax                         ; past its right edge: nearer than before
.skip:
    mov rax, [rax + Output.next]
    jmp .next
.fallback:
    mov rax, r8
.found:
    ret

; ---------------------------------------------------------------------------
; compositor_layout_bounds
;   The rectangle all outputs span, mirrors aside
;   IN:  rdi = server*
;   OUT: eax = left, edx = top, ecx = right (exclusive), r8d = bottom
;        (exclusive); all 0 with no output
; ---------------------------------------------------------------------------
global compositor_layout_bounds
compositor_layout_bounds:
    mov r9, [rdi + Server.outputs]
    xor eax, eax
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
.first:
    test r9, r9
    jz .done
    cmp qword [r9 + Output.mirror_of], 0
    je .start
    mov r9, [r9 + Output.next]
    jmp .first
.start:
    mov eax, [r9 + Output.x]
    mov edx, [r9 + Output.y]
    mov ecx, eax
    add ecx, [r9 + Output.width]
    mov r8d, edx
    add r8d, [r9 + Output.height]
.next:
    mov r9, [r9 + Output.next]
    test r9, r9
    jz .done
    cmp qword [r9 + Output.mirror_of], 0
    jne .next
    mov r10d, [r9 + Output.x]
    cmp r10d, eax
    cmovl eax, r10d
    add r10d, [r9 + Output.width]
    cmp r10d, ecx
    cmovg ecx, r10d
    mov r10d, [r9 + Output.y]
    cmp r10d, edx
    cmovl edx, r10d
    add r10d, [r9 + Output.height]
    cmp r10d, r8d
    cmovg r8d, r10d
    jmp .next
.done:
    ret

; ---------------------------------------------------------------------------
; compositor_restack_surface
;   Its level changed: to the top of its new level, redrawn
;   IN:  rdi = server*, rsi = surface*
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global compositor_restack_surface
compositor_restack_surface:
    PROLOGUE_SAVE rbx, r12, r13
    sub rsp, 8                          ; 16-byte aligned
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov r13, [r12 + Surface.output]
    test r13, r13
    jz .done
    mov rdi, rbx                        ; what it covered where it was
    mov rsi, r12
    call compositor_damage_surface
    mov rax, [r12 + Surface.z_order_prev]
    mov rcx, [r12 + Surface.z_order_next]
    test rcx, rcx
    jz .no_above
    mov [rcx + Surface.z_order_prev], rax
.no_above:
    test rax, rax
    jz .was_bottom
    mov [rax + Surface.z_order_next], rcx
    jmp .relink
.was_bottom:
    mov [rbx + Server.stack], rcx
.relink:
    mov rdi, r13
    mov rsi, r12
    call compositor_add_surface
.done:
    xor eax, eax
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13

; ---------------------------------------------------------------------------
; compositor_remove_surface
;   Take a surface off the screen; what it covered needs redrawing
;   IN:  rdi = server*, rsi = surface*
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global compositor_remove_surface
compositor_remove_surface:
    PROLOGUE_SAVE rbx, r12, r13
    sub rsp, 8                          ; 16-byte aligned
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov r13, [r12 + Surface.output]
    test r13, r13
    jz .done
    call compositor_damage_surface      ; its area, if it showed anything

.unlink:
    mov rax, [r12 + Surface.z_order_prev]
    mov rcx, [r12 + Surface.z_order_next]
    test rax, rax
    jz .was_bottom
    mov [rax + Surface.z_order_next], rcx
    jmp .after
.was_bottom:
    mov [rbx + Server.stack], rcx
.after:
    test rcx, rcx
    jz .cleared
    mov [rcx + Surface.z_order_prev], rax
.cleared:
    mov qword [r12 + Surface.output], 0
.done:
    xor eax, eax
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; compositor_composite
;   Composite all outputs for current frame
;   IN:  rdi = compositor*
;   OUT: rax = 0 OK, negative error
; ---------------------------------------------------------------------------
global compositor_composite
compositor_composite:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    ASSERT_PTR rbx

    mov rdi, [rbx + Compositor.server]  ; every surface's new damage first
    call compositor_collect_damage
    test rax, rax
    js .out
    mov rax, [rbx + Compositor.server]
    mov r12, [rax + Server.outputs]
.output_loop:
    test r12, r12
    jz .done
    cmp qword [r12 + Output.mirror_of], 0
    jne .next_output                    ; copied when its source is drawn
    mov rdi, rbx
    mov rsi, r12
    call compositor_composite_output
    test rax, rax
    js .out
.next_output:
    mov r12, [r12 + Output.next]
    jmp .output_loop
.done:
    xor eax, eax
.out:
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; compositor_damage_rect
;   A rectangle of the layout needs redrawing on every output it touches
;   IN:  rdi = server*, rsi = rect*
;   OUT: rax = 0, negative error
; ---------------------------------------------------------------------------
global compositor_damage_rect
compositor_damage_rect:
    PROLOGUE_SAVE rbx, r12, r13
    sub rsp, 8                          ; 16-byte aligned
    mov r12, rsi
    mov r13, [rdi + Server.outputs]
.output:
    test r13, r13
    jz .done
    cmp qword [r13 + Output.mirror_of], 0
    jne .next                           ; a mirror copies its source's
    mov eax, [r12]                      ; does it touch this one?
    mov ecx, [r13 + Output.x]
    add ecx, [r13 + Output.width]
    cmp eax, ecx
    jge .next
    add eax, [r12 + 8]
    cmp eax, [r13 + Output.x]
    jle .next
    mov eax, [r12 + 4]
    mov ecx, [r13 + Output.y]
    add ecx, [r13 + Output.height]
    cmp eax, ecx
    jge .next
    add eax, [r12 + 12]
    cmp eax, [r13 + Output.y]
    jle .next
    mov rdi, [r13 + Output.damage]
    mov rsi, r12
    call region_add_rect
    test rax, rax
    js .out
.next:
    mov r13, [r13 + Output.next]
    jmp .output
.done:
    xor eax, eax
.out:
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13

; ---------------------------------------------------------------------------
; compositor_damage_all
;   Every output needs redrawing, all of it (the screen locked or unlocked)
;   IN:  rdi = server*
;   OUT: rax = 0, negative error
; ---------------------------------------------------------------------------
global compositor_damage_all
compositor_damage_all:
    PROLOGUE_SAVE rbx
    sub rsp, 24                         ; a rect; 16-byte aligned
    mov rbx, [rdi + Server.outputs]
.output:
    test rbx, rbx
    jz .done
    cmp qword [rbx + Output.mirror_of], 0
    jne .next                           ; its source's copy will do
    mov eax, [rbx + Output.x]
    mov [rsp], eax
    mov eax, [rbx + Output.y]
    mov [rsp + 4], eax
    mov eax, [rbx + Output.width]
    mov [rsp + 8], eax
    mov eax, [rbx + Output.height]
    mov [rsp + 12], eax
    mov rdi, [rbx + Output.damage]
    mov rsi, rsp
    call region_add_rect
    test rax, rax
    js .out
.next:
    mov rbx, [rbx + Output.next]
    jmp .output
.done:
    xor eax, eax
.out:
    add rsp, 24
    EPILOGUE_RESTORE rbx

; ---------------------------------------------------------------------------
; compositor_collect_damage
;   Every surface's committed damage to the outputs it touches, in the
;   layout's coordinates; once a frame, before any output is drawn
;   IN:  rdi = server*
;   OUT: rax = 0, negative error
; ---------------------------------------------------------------------------
compositor_collect_damage:
    PROLOGUE_SAVE rbx, r12, r13, r14
    sub rsp, 32                         ; a rect; 16-byte aligned
    mov rbx, rdi
    mov r12, [rbx + Server.stack]
.surface:
    test r12, r12
    jz .done
    mov r13, [r12 + Surface.current + SurfaceState.damage]
    xor r14d, r14d
.rect:
    cmp r14, [r13 + Region.count]
    jae .surface_done
    mov rax, r14
    shl rax, 4
    add rax, [r13 + Region.rects]
    mov rcx, [rax]                      ; in the buffer's pixels
    mov [rsp], rcx
    mov rcx, [rax + 8]
    mov [rsp + 8], rcx
    mov rdi, rsp                        ; in the surface's, on the screen
    mov esi, [r12 + Surface.buffer_scale]
    call rect_to_surface
    mov ecx, [r12 + Surface.current + SurfaceState.buf_x]
    add [rsp], ecx
    mov ecx, [r12 + Surface.current + SurfaceState.buf_y]
    add [rsp + 4], ecx
    mov rdi, rbx
    mov rsi, rsp
    call compositor_damage_rect
    test rax, rax
    js .out
    inc r14
    jmp .rect
.surface_done:
    mov rdi, r13
    call region_clear
    mov r12, [r12 + Surface.z_order_next]
    jmp .surface
.done:
    xor eax, eax
.out:
    add rsp, 32
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; compositor_composite_output
;   Composite single output
;   IN:  rdi = compositor*, rsi = output*
;   OUT: rax = 0 OK, negative error
; ---------------------------------------------------------------------------
compositor_composite_output:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, FrameCtx_size + 64 + 8     ; ctx, whole output, clipped rect
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

%define L_BOUNDS    (FrameCtx_size)
%define L_CLIP      (FrameCtx_size + 16)

    mov r13, [r12 + Output.damage]
    test r13, r13
    jz .idle
    mov rdi, r13
    call region_is_empty
    test rax, rax
    jnz .idle

    mov rdi, [rbx + Compositor.renderer]
    mov rsi, r12
    mov rdx, r13
    mov rcx, rsp
    call sw_render_begin_frame

    mov eax, [r12 + Output.x]           ; the output, in the layout
    mov [rsp + L_BOUNDS], eax
    mov eax, [r12 + Output.y]
    mov [rsp + L_BOUNDS + 4], eax
    mov eax, [r12 + Output.width]
    mov [rsp + L_BOUNDS + 8], eax
    mov eax, [r12 + Output.height]
    mov [rsp + L_BOUNDS + 12], eax
    mov rdi, [rbx + Compositor.server]  ; zoomed: all of it, every frame
    mov rsi, r13
    lea rdx, [rsp + L_BOUNDS]
    call magnify_frame

    ; Every damaged rectangle, background first and each surface over it
    xor r14d, r14d
.rect:
    cmp r14, [r13 + Region.count]
    jae .rendered
    lea rdi, [rsp + L_CLIP]
    mov rsi, r14
    shl rsi, 4
    add rsi, [r13 + Region.rects]
    lea rdx, [rsp + L_BOUNDS]
    call rect_intersect
    test rax, rax
    jnz .next_rect
    mov rdi, [rbx + Compositor.server]  ; what covers it, from the top
    mov rsi, r12
    lea rdx, [rsp + L_CLIP]
    call topmost_cover
    mov r15, rax
    test r15, r15
    jnz .surface                        ; nothing under it shows
    mov rdi, rsp
    lea rsi, [rsp + L_CLIP]
    mov edx, [rbx + Compositor.bg_color]
    call sw_render_rect
    mov rax, [rbx + Compositor.server]
    mov r15, [rax + Server.stack]
.surface:
    test r15, r15
    jz .overlays
    mov rax, [rbx + Compositor.server]
    LOCK_HIDES rax, r15, .hidden
    mov rdi, rsp                        ; its title bar under it, if any
    mov rsi, r15
    lea rdx, [rsp + L_CLIP]
    call titlebar_render
    mov rdi, rsp
    mov rsi, r15
    lea rdx, [rsp + L_CLIP]
    call sw_render_surface
    inc qword [rbx + Compositor.drawn]
.hidden:
    mov r15, [r15 + Surface.z_order_next]
    jmp .surface
.overlays:
    mov rdi, rsp                        ; an Alt+Tab over everything
    lea rsi, [rsp + L_CLIP]
    call switcher_render
    mov rdi, rsp                        ; a drag's icon over that
    lea rsi, [rsp + L_CLIP]
    mov rdx, [rbx + Compositor.server]
    call dnd_render_icon
    mov rdi, rsp                        ; and the pointer over everything
    lea rsi, [rsp + L_CLIP]
    mov rdx, [rbx + Compositor.server]
    call sw_cursor_render
.next_rect:
    inc r14
    jmp .rect

.rendered:
    mov rdi, [rbx + Compositor.renderer]
    mov rsi, rsp
    call sw_render_end_frame
    mov rdi, [rbx + Compositor.server]  ; zoomed: round the pointer
    mov rsi, r12
    call magnify_output

    ; To its pixels (scaled, at a scale) and the backend's display memory
    mov rdi, r12
    mov rsi, r13
    call output_present
    mov rdi, rbx                        ; its mirrors, from what was drawn
    mov rsi, r12
    mov rdx, r13
    call mirror_copy
    mov rdi, r13
    call region_clear
    inc qword [rbx + Compositor.frame_seq]

    ; The frame is done: callbacks, then presentation feedback, for the
    ; surfaces this is the own output of (once each, with many outputs)
    call ut_time_now_ns
    mov r14, rax
    mov r13, [rbx + Compositor.server]
    mov r15, [r13 + Server.stack]
.finish:
    test r15, r15
    jz .idle
    cmp [r15 + Surface.output], r12
    jne .finished
    mov rdi, r15
    call surface_fire_frame_callbacks
.feedback:
    mov rdi, r13
    mov rsi, r15
    mov rdx, r14
    call presentation_complete
    test rax, rax
    jz .feedback                        ; until none is outstanding
.finished:
    mov r15, [r15 + Surface.z_order_next]
    jmp .finish

.idle:
    xor eax, eax
.out:
    add rsp, FrameCtx_size + 64 + 8
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; rdi = a rect in a buffer's pixels, esi = the buffer's scale in 120ths (0
; or 120: as it is): in the surface's units, rounded outwards
rect_to_surface:
    test esi, esi
    jz .same
    cmp esi, 120
    je .same
%macro TO_SURFACE 2                     ; the start's slot, the size's
    mov eax, [rdi + %1]                 ; the end, rounded up
    add eax, [rdi + %2]
    imul eax, eax, 120
    add eax, esi
    dec eax
    xor edx, edx
    div esi
    mov r9d, eax
    mov eax, [rdi + %1]                 ; the start, rounded down
    imul eax, eax, 120
    xor edx, edx
    div esi
    mov [rdi + %1], eax
    sub r9d, eax
    mov [rdi + %2], r9d
%endmacro
    TO_SURFACE 0, 8
    TO_SURFACE 4, 12
.same:
    ret

; Every output mirroring one just drawn: each damaged rectangle, mapped
; into the mirror (rounded outwards, then wider by what one source pixel
; spans there and two more, for the mirror pixels that blend it in), scaled
; from the source's pixels, then shown as that mirror's damage.
; rdi = compositor, rsi = the source, rdx = its damage (the layout's)
%define MC_JOB      0
%define MC_RECT     UgfxScale_SIZE      ; x0, y0, x1, y1 in the source, then
mirror_copy:                            ; x, y, w, h in the mirror
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, UgfxScale_SIZE + 16 + 8    ; the job, a rect; 16-byte aligned
    mov rbx, [rdi + Compositor.server]
    mov r12, rsi
    mov r13, rdx
    mov r14, [rbx + Server.outputs]
.output:
    test r14, r14
    jz .done
    cmp [r14 + Output.mirror_of], r12
    jne .next_output
    mov rax, [r14 + Output.framebuffer]
    mov [rsp + MC_JOB + UgfxScale_dst], rax
    mov rax, [r14 + Output.stride]
    mov [rsp + MC_JOB + UgfxScale_dst_stride], rax
    mov eax, [r14 + Output.width]
    mov [rsp + MC_JOB + UgfxScale_dst_w], eax
    mov eax, [r14 + Output.height]
    mov [rsp + MC_JOB + UgfxScale_dst_h], eax
    mov rax, [r12 + Output.framebuffer]
    mov [rsp + MC_JOB + UgfxScale_src], rax
    mov rax, [r12 + Output.stride]
    mov [rsp + MC_JOB + UgfxScale_src_stride], rax
    mov eax, [r12 + Output.width]
    mov [rsp + MC_JOB + UgfxScale_src_w], eax
    mov eax, [r12 + Output.height]
    mov [rsp + MC_JOB + UgfxScale_src_h], eax
    xor r15d, r15d
.rect:
    cmp r15, [r13 + Region.count]
    jae .show
    mov rax, r15
    shl rax, 4
    add rax, [r13 + Region.rects]
    mov ecx, [rax]                      ; in the source's own pixels, inside it
    sub ecx, [r12 + Output.x]
    mov edx, [rax + 4]
    sub edx, [r12 + Output.y]
    mov r8d, ecx
    add r8d, [rax + 8]
    mov r9d, edx
    add r9d, [rax + 12]
    xor eax, eax
    cmp ecx, eax
    cmovl ecx, eax
    cmp edx, eax
    cmovl edx, eax
    cmp r8d, [r12 + Output.width]
    cmovg r8d, [r12 + Output.width]
    cmp r9d, [r12 + Output.height]
    cmovg r9d, [r12 + Output.height]
    cmp r8d, ecx
    jle .next_rect
    cmp r9d, edx
    jle .next_rect
    mov [rsp + MC_RECT], ecx
    mov [rsp + MC_RECT + 4], edx
    mov [rsp + MC_RECT + 8], r8d
    mov [rsp + MC_RECT + 12], r9d
%macro MC_MAP 4                         ; slot, mirror's size, source's, 1: up
    mov eax, [rsp + MC_RECT + %1]
    mul dword [r14 + Output.%2]
  %if %4
    mov ecx, [r12 + Output.%3]
    dec ecx
    add eax, ecx
    adc edx, 0
  %endif
    div dword [r12 + Output.%3]
    mov [rsp + MC_RECT + %1], eax
%endmacro
    MC_MAP 0, width, width, 0
    MC_MAP 4, height, height, 0
    MC_MAP 8, width, width, 1
    MC_MAP 12, height, height, 1
%macro MC_WIDEN 3                       ; the start's slot, the end's, size
    mov eax, [r14 + Output.%3]
    xor edx, edx
    div dword [r12 + Output.%3]
    add eax, 2
    mov ecx, [rsp + MC_RECT + %1]
    sub ecx, eax
    xor edx, edx
    cmp ecx, edx
    cmovl ecx, edx
    mov [rsp + MC_RECT + %1], ecx
    mov ecx, [rsp + MC_RECT + %2]
    add ecx, eax
    cmp ecx, [r14 + Output.%3]
    cmovg ecx, [r14 + Output.%3]
    mov [rsp + MC_RECT + %2], ecx
%endmacro
    MC_WIDEN 0, 8, width
    MC_WIDEN 4, 12, height
    mov eax, [rsp + MC_RECT]
    mov [rsp + MC_JOB + UgfxScale_x], eax
    mov ecx, [rsp + MC_RECT + 8]
    sub ecx, eax
    jle .next_rect
    mov [rsp + MC_JOB + UgfxScale_w], ecx
    mov [rsp + MC_RECT + 8], ecx
    mov eax, [rsp + MC_RECT + 4]
    mov [rsp + MC_JOB + UgfxScale_y], eax
    mov ecx, [rsp + MC_RECT + 12]
    sub ecx, eax
    jle .next_rect
    mov [rsp + MC_JOB + UgfxScale_h], ecx
    mov [rsp + MC_RECT + 12], ecx
    lea rdi, [rsp + MC_JOB]
    call scale_bilinear_rect
    mov eax, [r14 + Output.x]           ; the mirror's damage, in the layout
    add [rsp + MC_RECT], eax
    mov eax, [r14 + Output.y]
    add [rsp + MC_RECT + 4], eax
    mov rdi, [r14 + Output.damage]
    lea rsi, [rsp + MC_RECT]
    call region_add_rect
.next_rect:
    inc r15
    jmp .rect
.show:
    mov rdi, r14                        ; to its pixels and display memory
    mov rsi, [r14 + Output.damage]
    call output_present
    mov rdi, [r14 + Output.damage]
    call region_clear
.next_output:
    mov r14, [r14 + Output.next]
    jmp .output
.done:
    add rsp, UgfxScale_SIZE + 16 + 8
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15

; The topmost surface that is opaque over the whole of a rectangle (the
; layout's coordinates), 0 if none is; any output's.
; rdi = server, rsi = Output*, rdx = rect* -> rax = Surface* or 0
topmost_cover:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, 8                          ; 16-byte aligned
    mov rbx, rdi
    mov r13, rdx
    xor r14d, r14d                      ; the latest found
    mov r12, [rbx + Server.stack]
.next:
    test r12, r12
    jz .done
    LOCK_HIDES rbx, r12, .skip
    mov rsi, [r12 + Surface.current + SurfaceState.buffer]
    test rsi, rsi
    jz .skip
    mov rdi, [rbx + Server.buffer_table]
    call handle_resolve
    test rax, rax
    jz .skip
    mov r15, rax                        ; the buffer
    mov ecx, [r12 + Surface.buffer_scale]   ; scaled: it may not cover
    test ecx, ecx                           ; every pixel it is over
    jz .unscaled
    cmp ecx, 120
    jne .skip
.unscaled:
    ; the rectangle in the surface's coordinates, inside the buffer
    mov eax, [r13]
    sub eax, [r12 + Surface.current + SurfaceState.buf_x]
    js .skip
    mov ecx, [r13 + 4]
    sub ecx, [r12 + Surface.current + SurfaceState.buf_y]
    js .skip
    mov edx, eax
    add edx, [r13 + 8]                  ; x1
    cmp edx, [r15 + Buffer.width]
    ja .skip
    mov r8d, ecx
    add r8d, [r13 + 12]                 ; y1
    cmp r8d, [r15 + Buffer.height]
    ja .skip
    cmp dword [r15 + Buffer.format], DRM_FORMAT_BGR8888
    je .covers                          ; no alpha: opaque everywhere
    mov r9, [r12 + Surface.current + SurfaceState.opaque]
    test r9, r9
    jz .skip
    mov r10, [r9 + Region.rects]
    mov r11, [r9 + Region.count]
.rect:
    test r11, r11
    jz .skip
    cmp [r10], eax                      ; its left at or before ours
    jg .next_rect
    cmp [r10 + 4], ecx
    jg .next_rect
    mov edi, [r10]
    add edi, [r10 + 8]
    cmp edi, edx                        ; its right at or after ours
    jl .next_rect
    mov edi, [r10 + 4]
    add edi, [r10 + 12]
    cmp edi, r8d
    jge .covers
.next_rect:
    add r10, 16
    dec r11
    jmp .rect
.covers:
    mov r14, r12
.skip:
    mov r12, [r12 + Surface.z_order_next]
    jmp .next
.done:
    mov rax, r14
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15

; ---------------------------------------------------------------------------
; compositor_schedule_frame
;   Schedule frame for output
; ---------------------------------------------------------------------------
global compositor_schedule_frame
compositor_schedule_frame:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Schedule frame clock callback
    mov rdi, [r12 + Output.frame_clock]
    lea rsi, [rel compositor_frame_callback]
    mov rdx, r12
    call frame_clock_schedule

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; compositor_frame_callback
;   Frame clock callback - triggers composition
; ---------------------------------------------------------------------------
compositor_frame_callback:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Composite
    mov rdi, rbx
    call compositor_composite

    ; Schedule next frame if damage
    mov rdi, [r12 + Output.damage]
    call region_is_empty
    test rax, rax
    jnz .done

    ; Has damage - schedule next
    mov rdi, rbx
    mov rsi, r12
    call compositor_schedule_frame

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

section .data

global compositor_version
compositor_version: dq 0x010100
