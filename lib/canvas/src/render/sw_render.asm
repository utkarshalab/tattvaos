; ============================================================================
; Software Renderer — Core Compositor (Damage-Driven, SIMD Blend)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/render.inc"
%include "inc/backend.inc"
%include "inc/color.inc"
%include "inc/struct_offsets.inc"
%include "inc/externs.inc"

section .text

; ---------------------------------------------------------------------------
; sw_render_init
;   Initialize software renderer
;   IN:  rdi = renderer*, rsi = backend*, rdx = arena
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global sw_render_init
sw_render_init:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13

    mov qword [rbx + Renderer.backend], r12
    mov qword [rbx + Renderer.arena], r13

    ; Set function pointers
    mov qword [rbx + Renderer.begin_frame], sw_render_begin_frame
    mov qword [rbx + Renderer.render_surface], sw_render_surface
    mov qword [rbx + Renderer.render_rect], sw_render_rect
    mov qword [rbx + Renderer.end_frame], sw_render_end_frame
    mov qword [rbx + Renderer.flush], sw_render_flush
    mov qword [rbx + Renderer.caps], RENDER_CAP_BLEND | RENDER_CAP_SCALE | RENDER_CAP_TRANSFORM | RENDER_CAP_DIRECT_SCANOUT

    ; Initialize blend dispatch (patched by cpuid)
    mov rax, blend_dispatch
    mov [rbx + Renderer.blend_fn], rax

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; sw_render_deinit
; ---------------------------------------------------------------------------
global sw_render_deinit
sw_render_deinit:
    PROLOGUE
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; sw_render_begin_frame
;   Begin frame composition
;   IN:  rdi = renderer*, rsi = output*, rdx = damage_region*
;   OUT: rax = frame_ctx*, negative error
; ---------------------------------------------------------------------------
global sw_render_begin_frame
sw_render_begin_frame:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Allocate frame context
    mov rdi, [rbx + Renderer.arena]
    mov rsi, FrameCtx_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov r14, rax

    ; Fill frame context
    mov qword [r14 + FrameCtx.output], r12
    mov qword [r14 + FrameCtx.damage], r13
    mov qword [r14 + FrameCtx.render_list], 0

    ; Get output framebuffer
    mov rax, [r12 + Output.framebuffer]
    mov [r14 + FrameCtx.framebuffer], rax
    mov rax, [r12 + Output.stride]
    mov [r14 + FrameCtx.stride], rax
    mov eax, [r12 + Output.width]
    mov [r14 + FrameCtx.width], eax
    mov eax, [r12 + Output.height]
    mov [r14 + FrameCtx.height], eax

    ; Get color transform for output
    mov rax, [r12 + Output.icc_profile]
    test rax, rax
    jz .no_transform
    mov [r14 + FrameCtx.color_transform], rax
    jmp .transform_done
.no_transform:
    mov qword [r14 + FrameCtx.color_transform], 0
.transform_done:

    mov rax, r14
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; sw_render_surface
;   Composite surface into frame
;   IN:  rdi = frame_ctx*, rsi = surface*, rdx = clip_rect*
; ---------------------------------------------------------------------------
global sw_render_surface
sw_render_surface:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Get surface current state
    mov r14, [r12 + Surface.buffer]
    test r14, r14
    jz .no_buffer

    ; Check buffer state
    cmp byte [r14 + Buffer.state], 2  ; ATTACHED
    jne .bad_state
    cmp byte [r14 + Buffer.state], 3  ; SCANOUT
    je .scanout_buffer

    ; Get surface transform
    mov eax, [r12 + Surface.current + SurfaceState.transform]
    mov r15d, eax

    ; Get surface scale
    mov r9, [r12 + Surface.current + SurfaceState.scale]

    ; Get surface position
    mov eax, [r12 + Surface.current + SurfaceState.buf_x]
    mov r10d, eax
    mov eax, [r12 + Surface.current + SurfaceState.buf_y]
    mov r11d, eax

    test r9, r9
    jnz .scale_valid
    mov r9, 0x10000
.scale_valid:
    imul r10, r9
    sar r10, 16
    imul r11, r9
    sar r11, 16

    ; Composite surface
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r14
    mov rcx, r10
    mov r8, r11
    call sw_composite_surface
    jmp .rendered

.scanout_buffer:
    mov byte [r14 + Buffer.state], 3
.rendered:
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.bad_state:
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.bad_buffer:
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.no_buffer:
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.no_damage:
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; sw_composite_surface (internal)
;   Composite single surface with blend
; ---------------------------------------------------------------------------
sw_composite_surface:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    ; rbx = frame_ctx, r12 = surface, r13 = buffer, r14 = dst_x, r15 = dst_y

    ; Get buffer data
    mov rdi, [r13 + Buffer.base]
    mov rsi, [rbx + FrameCtx.framebuffer]
    lea rsi, [rsi + r14 * 4]
    imul r15, [rbx + FrameCtx.stride]
    add rsi, r15

    ; Get dimensions
    mov edx, [r13 + Buffer.width]
    mov ecx, [r13 + Buffer.height]
    mov r8, [r13 + Buffer.stride]
    mov r9, [rbx + FrameCtx.stride]

    ; Call blend dispatch
    call blend_dispatch

    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; sw_render_rect
;   Fill rect with color (for opaque regions, decorations)
; ---------------------------------------------------------------------------
global sw_render_rect
sw_render_rect:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    ASSERT_PTR rbx

    ; Get framebuffer
    mov rax, [rbx + FrameCtx.framebuffer]

    ; Fill rect
    mov rdi, rax
    mov rsi, r12
    mov rdx, r13
    mov rcx, r14
    mov r8, [rbx + FrameCtx.stride]
    call fill_solid

    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; sw_render_end_frame
;   End frame, return present info
;   IN:  rdi = renderer*, rsi = frame_ctx*
;   OUT: rax = PresentInfo*
; ---------------------------------------------------------------------------
global sw_render_end_frame
sw_render_end_frame:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Allocate present info
    mov rdi, [rbx + Renderer.arena]
    mov rsi, PresentInfo_size
    call arena_alloc
    test rax, rax
    jz .oom

    ; Fill present info
    mov dword [rax + PresentInfo.kind], PRESENT_KIND_VSYNC
    mov rdx, 1
    lock xadd [rel sw_present_seq], rdx
    inc rdx
    mov qword [rax + PresentInfo.seq], rdx
    mov qword [rax + PresentInfo.time], 0 ; filled by vblank
    mov qword [rax + PresentInfo.refresh_ns], 16666667
    mov dword [rax + PresentInfo.flags], 0

    EPILOGUE_RESTORE rbx, r12
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; sw_render_flush
;   Flush pending operations (no-op for SW)
; ---------------------------------------------------------------------------
global sw_render_flush
sw_render_flush:
    PROLOGUE
    xor rax, rax
    leave
    ret

section .data
sw_present_seq: dq 0

global sw_render_version
sw_render_version: dq 0x010000
