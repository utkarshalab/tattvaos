; ============================================================================
; Compositor — Damage-Driven Composition Driver
; Coordinates renderer, damage tracking, frame scheduling
; ============================================================================
; Each output keeps its surfaces bottom to top in Output.surfaces, linked by
; z_order_next / z_order_prev, in stacking levels (LEVEL_* in
; inc/struct_offsets.inc; a surface's is its shell role's, LEVEL_NORMAL with
; none). A surface goes in, or is raised, to the top of its own level. A frame moves each surface's committed damage
; to the output, redraws every damaged rectangle from the background up, then
; tells the surfaces their frame is done. Nothing damaged means no frame.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/render.inc"
%include "inc/backend.inc"
%include "inc/struct_offsets.inc"

extern arena_alloc
extern frame_clock_schedule
extern handle_resolve
extern presentation_complete
extern rect_intersect
extern region_add_rect
extern region_clear
extern region_is_empty
extern surface_fire_frame_callbacks
extern sw_render_init
extern sw_render_begin_frame
extern sw_render_rect
extern sw_render_surface
extern sw_render_end_frame

%define COMPOSITOR_BG_COLOR 0xFF202030  ; opaque BGRA

; %1 = Surface* register -> %2 = its stacking level (32-bit register); uses r10
%macro LEVEL_OF 2
    xor %2, %2
    mov r10, [%1 + Surface.window]
    test r10, r10
    jz %%done
    mov %2, [r10 + Window.level]
%%done:
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
;   Put a surface on an output, above everything at its level or below
;   IN:  rdi = output*, rsi = surface*
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global compositor_add_surface
compositor_add_surface:
    ASSERT_PTR rdi
    ASSERT_PTR rsi
    mov [rsi + Surface.output], rdi
    LEVEL_OF rsi, r8d
    xor ecx, ecx                        ; the one it goes above; 0: the bottom
    mov rax, [rdi + Output.surfaces]
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
    mov [rdi + Output.surfaces], rsi
.done:
    xor eax, eax
    ret

; ---------------------------------------------------------------------------
; compositor_damage_surface
;   What a surface shows needs redrawing on its output
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
    mov rcx, [rax + Buffer.width]
    mov [rsp + 8], ecx
    mov rcx, [rax + Buffer.height]
    mov [rsp + 12], ecx
    mov rdi, [r13 + Output.damage]
    mov rsi, rsp
    call region_add_rect
.done:
    xor eax, eax
    add rsp, 24
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; compositor_raise_surface
;   Put a surface above everything else at its level on its output
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
    mov [r13 + Output.surfaces], rcx
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
    mov [r13 + Output.surfaces], rcx
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
;   Take a surface off its output; what it covered needs redrawing
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
    mov [r13 + Output.surfaces], rcx
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

    mov rax, [rbx + Compositor.server]
    mov r12, [rax + Server.outputs]
.output_loop:
    test r12, r12
    jz .done
    mov rdi, rbx
    mov rsi, r12
    call compositor_composite_output
    test rax, rax
    js .out
    mov r12, [r12 + Output.next]
    jmp .output_loop
.done:
    xor eax, eax
.out:
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; compositor_collect_damage
;   Move committed surface damage to the output, in output coordinates
;   IN:  rdi = output*
;   OUT: rax = 0, negative error
; ---------------------------------------------------------------------------
compositor_collect_damage:
    PROLOGUE_SAVE rbx, r12, r13, r14
    sub rsp, 32                         ; a rect; 16-byte aligned
    mov rbx, rdi
    mov r12, [rbx + Output.surfaces]
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
    mov ecx, [rax]
    add ecx, [r12 + Surface.current + SurfaceState.buf_x]
    mov [rsp], ecx
    mov ecx, [rax + 4]
    add ecx, [r12 + Surface.current + SurfaceState.buf_y]
    mov [rsp + 4], ecx
    mov rcx, [rax + 8]                  ; width, height
    mov [rsp + 8], rcx
    mov rdi, [rbx + Output.damage]
    mov rsi, rsp
    call region_add_rect
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

    mov rdi, r12
    call compositor_collect_damage
    test rax, rax
    js .out
    mov rdi, r13
    call region_is_empty
    test rax, rax
    jnz .idle

    mov rdi, [rbx + Compositor.renderer]
    mov rsi, r12
    mov rdx, r13
    mov rcx, rsp
    call sw_render_begin_frame

    mov dword [rsp + L_BOUNDS], 0
    mov dword [rsp + L_BOUNDS + 4], 0
    mov eax, [r12 + Output.width]
    mov [rsp + L_BOUNDS + 8], eax
    mov eax, [r12 + Output.height]
    mov [rsp + L_BOUNDS + 12], eax

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
    mov rdi, rsp
    lea rsi, [rsp + L_CLIP]
    mov edx, [rbx + Compositor.bg_color]
    call sw_render_rect
    mov r15, [r12 + Output.surfaces]
.surface:
    test r15, r15
    jz .next_rect
    mov rdi, rsp
    mov rsi, r15
    lea rdx, [rsp + L_CLIP]
    call sw_render_surface
    mov r15, [r15 + Surface.z_order_next]
    jmp .surface
.next_rect:
    inc r14
    jmp .rect

.rendered:
    mov rdi, [rbx + Compositor.renderer]
    mov rsi, rsp
    call sw_render_end_frame

    ; A backend with real display memory takes the damage now
    mov rdi, [r12 + Output.backend]
    mov rax, [rdi + Backend.flip]
    test rax, rax
    jz .presented
    mov rsi, r12
    mov rdx, r13
    xor ecx, ecx
    call rax
.presented:
    mov rdi, r13
    call region_clear
    inc qword [rbx + Compositor.frame_seq]

    ; The frame is done: callbacks, then presentation feedback
    call ut_time_now_ns
    mov r14, rax
    mov r13, [rbx + Compositor.server]
    mov r15, [r12 + Output.surfaces]
.finish:
    test r15, r15
    jz .idle
    mov rdi, r15
    call surface_fire_frame_callbacks
.feedback:
    mov rdi, r13
    mov rsi, r15
    mov rdx, r14
    call presentation_complete
    test rax, rax
    jz .feedback                        ; until none is outstanding
    mov r15, [r15 + Surface.z_order_next]
    jmp .finish

.idle:
    xor eax, eax
.out:
    add rsp, FrameCtx_size + 64 + 8
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

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
