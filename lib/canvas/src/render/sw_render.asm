; ============================================================================
; Software Renderer — Core Compositor (Damage-Driven)
; ============================================================================
; A frame is a FrameCtx the caller provides, so frames allocate nothing. Each
; call draws inside one clip rectangle (x, y, w, h as i32) already within the
; output. Surfaces blend premultiplied BGRA row by row; a surface's position
; is its attach offset. Scale and transform are not applied yet (CMP work).

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/render.inc"
%include "inc/backend.inc"
%include "inc/color.inc"
%include "inc/struct_offsets.inc"

extern blend_over_premul
extern handle_resolve
extern memcopy

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
    lea rax, [rel sw_render_begin_frame]
    mov [rbx + Renderer.begin_frame], rax
    lea rax, [rel sw_render_surface]
    mov [rbx + Renderer.render_surface], rax
    lea rax, [rel sw_render_rect]
    mov [rbx + Renderer.render_rect], rax
    lea rax, [rel sw_render_end_frame]
    mov [rbx + Renderer.end_frame], rax
    lea rax, [rel sw_render_flush]
    mov [rbx + Renderer.flush], rax
    mov qword [rbx + Renderer.caps], RENDER_CAP_BLEND

    lea rax, [rel blend_over_premul]
    mov [rbx + Renderer.blend_fn], rax

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; sw_render_deinit
; ---------------------------------------------------------------------------
global sw_render_deinit
sw_render_deinit:
    xor eax, eax
    ret

; ---------------------------------------------------------------------------
; sw_render_begin_frame
;   Begin frame composition
;   IN:  rdi = renderer*, rsi = output*, rdx = damage_region*, rcx = FrameCtx*
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global sw_render_begin_frame
sw_render_begin_frame:
    ASSERT_PTR rdi
    ASSERT_PTR rsi
    ASSERT_PTR rcx
    mov rax, [rdi + Renderer.backend]
    mov rax, [rax + Backend.server]
    mov [rcx + FrameCtx.server], rax
    mov [rcx + FrameCtx.output], rsi
    mov [rcx + FrameCtx.damage], rdx
    mov qword [rcx + FrameCtx.render_list], 0
    ; The framebuffer as if it began at the layout's origin: everything is
    ; drawn in the layout's coordinates, the output's part of it landing
    ; in its own pixels
    movsxd rax, dword [rsi + Output.y]
    imul rax, [rsi + Output.stride]
    movsxd r8, dword [rsi + Output.x]
    lea rax, [rax + r8 * 4]
    neg rax
    add rax, [rsi + Output.framebuffer]
    mov [rcx + FrameCtx.framebuffer], rax
    mov rax, [rsi + Output.stride]
    mov [rcx + FrameCtx.stride], rax
    mov eax, [rsi + Output.width]
    mov [rcx + FrameCtx.width], eax
    mov eax, [rsi + Output.height]
    mov [rcx + FrameCtx.height], eax
    mov rax, [rsi + Output.icc_profile]
    mov [rcx + FrameCtx.color_transform], rax
    xor eax, eax
    ret

; ---------------------------------------------------------------------------
; sw_render_surface
;   Composite the part of a surface inside the clip rectangle
;   IN:  rdi = frame_ctx*, rsi = surface*, rdx = clip_rect*
;   OUT: rax = 0 (nothing attached or an unknown format draws nothing)
; ---------------------------------------------------------------------------
global sw_render_surface
sw_render_surface:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, 24                         ; row width, opaque flag, pad
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13

    mov rsi, [r12 + Surface.current + SurfaceState.buffer]
    test rsi, rsi
    jz .done
    mov rax, [rbx + FrameCtx.server]
    mov rdi, [rax + Server.buffer_table]
    call handle_resolve
    test rax, rax
    jz .done
    mov r14, rax                        ; buffer*

    mov eax, [r14 + Buffer.format]
    cmp eax, DRM_FORMAT_BGRA8888
    sete cl
    je .format_ok
    cmp eax, DRM_FORMAT_BGR8888
    jne .done
.format_ok:
    movzx ecx, cl
    xor ecx, 1
    mov [rsp + 8], rcx                  ; 1: no alpha, rows are copied

    ; The surface's rectangle, clipped
    movsxd rax, dword [r12 + Surface.current + SurfaceState.buf_x]    ; surface x
    movsxd rdx, dword [r12 + Surface.current + SurfaceState.buf_y]    ; surface y
    mov r8, [r14 + Buffer.width]
    add r8, rax                         ; surface right
    mov r9, [r14 + Buffer.height]
    add r9, rdx                         ; surface bottom
    movsxd r10, dword [r13 + 0]         ; left = max(surface, clip)
    cmp r10, rax
    cmovl r10, rax
    movsxd r11, dword [r13 + 4]         ; top
    cmp r11, rdx
    cmovl r11, rdx
    movsxd rcx, dword [r13 + 8]
    movsxd rdi, dword [r13 + 0]
    add rcx, rdi                        ; clip right
    cmp r8, rcx
    cmovg r8, rcx
    movsxd rcx, dword [r13 + 12]
    movsxd rdi, dword [r13 + 4]
    add rcx, rdi                        ; clip bottom
    cmp r9, rcx
    cmovg r9, rcx
    sub r8, r10                         ; width
    jle .done
    sub r9, r11                         ; rows
    jle .done
    mov [rsp], r8

    ; Row starts
    sub rax, r10
    neg rax                             ; offset into the surface, x
    sub rdx, r11
    neg rdx                             ; y
    imul rdx, [r14 + Buffer.stride]
    lea r12, [rdx + rax * 4]
    add r12, [r14 + Buffer.base]        ; source
    mov r13, r11
    imul r13, [rbx + FrameCtx.stride]
    lea r13, [r13 + r10 * 4]
    add r13, [rbx + FrameCtx.framebuffer]   ; destination
    mov r15, r9

.row:
    mov rdi, r13
    mov rsi, r12
    mov rdx, [rsp]
    cmp qword [rsp + 8], 0
    jne .copy
    call blend_over_premul
    jmp .next
.copy:
    shl rdx, 2
    call memcopy
.next:
    add r12, [r14 + Buffer.stride]
    add r13, [rbx + FrameCtx.stride]
    dec r15
    jnz .row

.done:
    xor eax, eax
    add rsp, 24
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; sw_render_rect
;   Fill a rectangle with a colour
;   IN:  rdi = frame_ctx*, rsi = rect*, rdx = colour (BGRA)
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global sw_render_rect
sw_render_rect:
    ASSERT_PTR rdi
    ASSERT_PTR rsi
    mov r8, rdi
    mov eax, edx                        ; the colour stosd writes
    movsxd rdx, dword [rsi + 4]
    imul rdx, [r8 + FrameCtx.stride]
    movsxd rcx, dword [rsi + 0]
    lea rdx, [rdx + rcx * 4]
    add rdx, [r8 + FrameCtx.framebuffer]    ; row start
    movsxd r9, dword [rsi + 12]         ; rows
.row:
    test r9, r9
    jle .done
    mov rdi, rdx
    mov ecx, [rsi + 8]
    rep stosd
    add rdx, [r8 + FrameCtx.stride]
    dec r9
    jmp .row
.done:
    xor eax, eax
    ret

; ---------------------------------------------------------------------------
; sw_render_end_frame
;   End frame
;   IN:  rdi = renderer*, rsi = frame_ctx*
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global sw_render_end_frame
sw_render_end_frame:
    xor eax, eax
    ret

; ---------------------------------------------------------------------------
; sw_render_flush
;   Flush pending operations (no-op for SW)
; ---------------------------------------------------------------------------
global sw_render_flush
sw_render_flush:
    xor eax, eax
    ret

section .data
global sw_render_version
sw_render_version: dq 0x010100
