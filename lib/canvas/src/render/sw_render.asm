; ============================================================================
; Software Renderer — Core Compositor (Damage-Driven)
; ============================================================================
; A frame is a FrameCtx the caller provides, so frames allocate nothing. Each
; call draws inside one clip rectangle (x, y, w, h as i32) already within the
; output. Surfaces blend premultiplied BGRA row by row; a surface's position
; is its attach offset. Transforms are not applied yet.
;
; Callers give rectangles in the layout's logical units. A frame of an
; output at a scale (FrameCtx.px_scale) is that output's pixels: each edge
; is mapped there and rounded to a whole pixel (frame_map_rect), so what
; meets in the layout meets on the screen (decision 0012, CMP-22). A buffer
; the size it comes out (within a pixel) is copied pixel for pixel, sharp;
; another is scaled to it.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/render.inc"
%include "inc/backend.inc"
%include "inc/color.inc"
%include "inc/struct_offsets.inc"
%include "ugfx.inc"
%include "inc/ui_text.inc"

extern blend_over_premul
extern handle_resolve
extern memcopy
extern scale_bilinear_rect
extern surface_logical_size
extern ui_text_draw

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
    mov dword [rcx + FrameCtx.px_scale], 0  ; the layout's units, until the
    mov dword [rcx + FrameCtx.px_ox], 0     ; compositor says pixels
    mov dword [rcx + FrameCtx.px_oy], 0
    xor eax, eax
    ret

; ---------------------------------------------------------------------------
; frame_map_rect
;   A rectangle of the layout in the frame: as it is in the layout's units;
;   in pixels, each edge (x - origin) * scale rounded to the nearest pixel
;   IN:  rdi = frame_ctx*, rsi = rect* in, rdx = rect* out (may be the same)
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global frame_map_rect
frame_map_rect:
    mov r8d, [rdi + FrameCtx.px_scale]
    test r8d, r8d
    jnz .map
    mov rax, [rsi]
    mov rcx, [rsi + 8]
    mov [rdx], rax
    mov [rdx + 8], rcx
    xor eax, eax
    ret
.map:
    push rbx
    push r12
    mov r12, rdx                        ; (idiv takes edx)
    mov r9d, [rsi]                      ; x0, x1
    mov r10d, r9d
    add r10d, [rsi + 8]
    mov r11d, [rsi + 4]                 ; y0, y1
    mov ebx, r11d
    add ebx, [rsi + 12]
    sub r9d, [rdi + FrameCtx.px_ox]
    sub r10d, [rdi + FrameCtx.px_ox]
    sub r11d, [rdi + FrameCtx.px_oy]
    sub ebx, [rdi + FrameCtx.px_oy]
%macro TO_PIXEL 1                       ; %1 = round(%1 * scale / 120)
    imul %1, r8d
    add %1, 60
    mov eax, %1
    cdq
    mov ecx, 120
    idiv ecx
    test edx, edx                       ; idiv truncates: floor it
    jns %%floored
    dec eax
%%floored:
    mov %1, eax
%endmacro
    TO_PIXEL r9d
    TO_PIXEL r10d
    TO_PIXEL r11d
    TO_PIXEL ebx
    mov [r12], r9d
    mov [r12 + 4], r11d
    sub r10d, r9d
    mov [r12 + 8], r10d
    sub ebx, r11d
    mov [r12 + 12], ebx
    pop r12
    pop rbx
    xor eax, eax
    ret

; ---------------------------------------------------------------------------
; frame_clip_rect
;   A clip rectangle in the frame: mapped (frame_map_rect) and, in pixels,
;   kept inside them
;   IN:  rdi = frame_ctx*, rsi = rect* in, rdx = rect* out
;   OUT: rax = 0, 1 if nothing is left
; ---------------------------------------------------------------------------
global frame_clip_rect
frame_clip_rect:
    push rbx
    mov rbx, rdx
    call frame_map_rect
    cmp dword [rdi + FrameCtx.px_scale], 0
    je .sized
    xor eax, eax                        ; inside 0..width, 0..height
    mov ecx, [rbx]
    mov edx, ecx
    add edx, [rbx + 8]
    cmp ecx, eax
    cmovl ecx, eax
    cmp edx, [rdi + FrameCtx.width]
    cmovg edx, [rdi + FrameCtx.width]
    mov [rbx], ecx
    sub edx, ecx
    mov [rbx + 8], edx
    mov ecx, [rbx + 4]
    mov edx, ecx
    add edx, [rbx + 12]
    cmp ecx, eax
    cmovl ecx, eax
    cmp edx, [rdi + FrameCtx.height]
    cmovg edx, [rdi + FrameCtx.height]
    mov [rbx + 4], ecx
    sub edx, ecx
    mov [rbx + 12], edx
.sized:
    mov eax, 1
    cmp dword [rbx + 8], 0
    jle .out
    cmp dword [rbx + 12], 0
    jle .out
    xor eax, eax
.out:
    pop rbx
    ret

; ---------------------------------------------------------------------------
; frame_text
;   ui_text_draw into the frame: its box and clip mapped, its size scaled
;   IN:  rdi = frame_ctx*, rsi = UiText* (in the layout's units; changed)
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global frame_text
frame_text:
    push rbx
    push r12
    sub rsp, 24                         ; a rect; 16-byte aligned
    mov rbx, rdi
    mov r12, rsi
    mov r8d, [rbx + FrameCtx.px_scale]
    test r8d, r8d
    jz .draw
    mov eax, [r12 + UiText.x]           ; its box
    mov [rsp], eax
    mov eax, [r12 + UiText.y]
    mov [rsp + 4], eax
    mov eax, [r12 + UiText.width]
    mov [rsp + 8], eax
    mov eax, [r12 + UiText.height]
    mov [rsp + 12], eax
    mov rdi, rbx
    mov rsi, rsp
    mov rdx, rsp
    call frame_map_rect
    mov eax, [rsp]
    mov [r12 + UiText.x], eax
    mov eax, [rsp + 4]
    mov [r12 + UiText.y], eax
    mov eax, [rsp + 8]
    mov [r12 + UiText.width], eax
    mov eax, [rsp + 12]
    mov [r12 + UiText.height], eax
    mov eax, [r12 + UiText.clip_x]      ; its clip
    mov [rsp], eax
    mov eax, [r12 + UiText.clip_y]
    mov [rsp + 4], eax
    mov eax, [r12 + UiText.clip_w]
    mov [rsp + 8], eax
    mov eax, [r12 + UiText.clip_h]
    mov [rsp + 12], eax
    mov rdi, rbx
    mov rsi, rsp
    mov rdx, rsp
    call frame_clip_rect
    test eax, eax
    jnz .out
    mov eax, [rsp]
    mov [r12 + UiText.clip_x], eax
    mov eax, [rsp + 4]
    mov [r12 + UiText.clip_y], eax
    mov eax, [rsp + 8]
    mov [r12 + UiText.clip_w], eax
    mov eax, [rsp + 12]
    mov [r12 + UiText.clip_h], eax
    mov eax, [r12 + UiText.size]        ; its size, rounded
    imul eax, [rbx + FrameCtx.px_scale]
    add eax, 60
    xor edx, edx
    mov ecx, 120
    div ecx
    mov [r12 + UiText.size], eax
.draw:
    mov rdi, r12
    call ui_text_draw
.out:
    xor eax, eax
    add rsp, 24
    pop r12
    pop rbx
    ret

; ---------------------------------------------------------------------------
; sw_render_surface
;   Composite the part of a surface inside the clip rectangle
;   IN:  rdi = frame_ctx*, rsi = surface*, rdx = clip_rect*
;   OUT: rax = 0 (nothing attached or an unknown format draws nothing)
; ---------------------------------------------------------------------------
%define S_WIDTH     0                   ; a row's pixels
%define S_NO_ALPHA  8                   ; 1: rows are copied
%define S_DEST      16                  ; where it goes, in the frame
%define S_CLIP      32                  ; the clip, in the frame
global sw_render_surface
sw_render_surface:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, 56                         ; locals; 16-byte aligned
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
    mov [rsp + S_NO_ALPHA], rcx

    ; Where it goes: its place and size in the layout, in the frame
    mov rdi, r12
    mov rsi, r14
    call surface_logical_size
    mov ecx, [r12 + Surface.current + SurfaceState.buf_x]
    mov [rsp + S_DEST], ecx
    mov ecx, [r12 + Surface.current + SurfaceState.buf_y]
    mov [rsp + S_DEST + 4], ecx
    mov [rsp + S_DEST + 8], eax
    mov [rsp + S_DEST + 12], edx
    mov rdi, rbx
    lea rsi, [rsp + S_DEST]
    mov rdx, rsi
    call frame_map_rect
    mov rdi, rbx
    mov rsi, r13
    lea rdx, [rsp + S_CLIP]
    call frame_clip_rect
    test eax, eax
    jnz .done

    ; A buffer that size, within a pixel, is copied as it is; another is
    ; scaled to it
    mov eax, [rsp + S_DEST + 8]
    sub eax, [r14 + Buffer.width]
    add eax, 1
    cmp eax, 2
    ja .scaled
    mov eax, [rsp + S_DEST + 12]
    sub eax, [r14 + Buffer.height]
    add eax, 1
    cmp eax, 2
    jbe .unscaled
.scaled:
    mov rdi, rbx
    lea rsi, [rsp + S_DEST]
    lea rdx, [rsp + S_CLIP]
    mov rcx, r14
    mov r8, [rsp + S_NO_ALPHA]
    call render_scaled
    jmp .done
.unscaled:

    ; Its rectangle (the buffer from the destination's corner, no further
    ; than the destination), clipped
    movsxd rax, dword [rsp + S_DEST]
    movsxd rdx, dword [rsp + S_DEST + 4]
    mov r8d, [r14 + Buffer.width]
    cmp r8d, [rsp + S_DEST + 8]
    cmova r8d, [rsp + S_DEST + 8]
    add r8, rax                         ; right
    mov r9d, [r14 + Buffer.height]
    cmp r9d, [rsp + S_DEST + 12]
    cmova r9d, [rsp + S_DEST + 12]
    add r9, rdx                         ; bottom
    movsxd r10, dword [rsp + S_CLIP]    ; left = max(it, clip)
    cmp r10, rax
    cmovl r10, rax
    movsxd r11, dword [rsp + S_CLIP + 4]    ; top
    cmp r11, rdx
    cmovl r11, rdx
    movsxd rcx, dword [rsp + S_CLIP + 8]
    movsxd rdi, dword [rsp + S_CLIP]
    add rcx, rdi                        ; clip right
    cmp r8, rcx
    cmovg r8, rcx
    movsxd rcx, dword [rsp + S_CLIP + 12]
    movsxd rdi, dword [rsp + S_CLIP + 4]
    add rcx, rdi                        ; clip bottom
    cmp r9, rcx
    cmovg r9, rcx
    sub r8, r10                         ; width
    jle .done
    sub r9, r11                         ; rows
    jle .done
    mov [rsp + S_WIDTH], r8

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
    mov rdx, [rsp + S_WIDTH]
    cmp qword [rsp + S_NO_ALPHA], 0
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
    add rsp, 56
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; A buffer scaled to its destination: the part inside the clip, each row
; scaled into scale_row (bilinear, premultiplied as the pixels are) and then
; blended, or copied with no alpha. Columns past SCALE_ROW_PX in one row are
; not drawn.
; rdi = frame_ctx, rsi = the destination rect, rdx = clip rect (both in the
; frame), rcx = the Buffer*, r8 = 1 with no alpha
%define SCALE_ROW_PX    4096
%define R_JOB           0
%define R_NO_ALPHA      (UgfxScale_SIZE + 0)
%define R_LEFT          (UgfxScale_SIZE + 8)
%define R_TOP           (UgfxScale_SIZE + 12)
%define R_WIDTH         (UgfxScale_SIZE + 16)
%define R_ROWS          (UgfxScale_SIZE + 20)
%define R_SX            (UgfxScale_SIZE + 24)
%define R_SY            (UgfxScale_SIZE + 28)
render_scaled:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, UgfxScale_SIZE + 40        ; the job, locals; 16-byte aligned
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov [rsp + R_NO_ALPHA], r8
    mov eax, [r12 + 8]                  ; the size it comes out
    mov edx, [r12 + 12]
    mov [rsp + R_JOB + UgfxScale_dst_w], eax
    mov [rsp + R_JOB + UgfxScale_dst_h], edx
    mov r8d, [r12]
    mov r9d, [r12 + 4]
    mov [rsp + R_SX], r8d
    mov [rsp + R_SY], r9d
    lea r10d, [r8 + rax]                ; right, bottom
    lea r11d, [r9 + rdx]
    mov eax, [r13]                      ; inside the clip
    cmp r8d, eax
    cmovl r8d, eax
    mov eax, [r13 + 4]
    cmp r9d, eax
    cmovl r9d, eax
    mov eax, [r13]
    add eax, [r13 + 8]
    cmp r10d, eax
    cmovg r10d, eax
    mov eax, [r13 + 4]
    add eax, [r13 + 12]
    cmp r11d, eax
    cmovg r11d, eax
    sub r10d, r8d
    jle .done
    sub r11d, r9d
    jle .done
    mov eax, SCALE_ROW_PX
    cmp r10d, eax
    cmovg r10d, eax
    mov [rsp + R_LEFT], r8d
    mov [rsp + R_TOP], r9d
    mov [rsp + R_WIDTH], r10d
    mov [rsp + R_ROWS], r11d
    mov eax, r8d                        ; the job: one row at a time into
    sub eax, [rsp + R_SX]               ; scale_row, its first column there
    mov [rsp + R_JOB + UgfxScale_x], eax
    mov [rsp + R_JOB + UgfxScale_w], r10d
    mov dword [rsp + R_JOB + UgfxScale_h], 1
    lea rcx, [rel scale_row]
    cdqe
    shl rax, 2
    sub rcx, rax
    mov [rsp + R_JOB + UgfxScale_dst], rcx
    mov qword [rsp + R_JOB + UgfxScale_dst_stride], 0
    mov rax, [r14 + Buffer.base]
    mov [rsp + R_JOB + UgfxScale_src], rax
    mov rax, [r14 + Buffer.stride]
    mov [rsp + R_JOB + UgfxScale_src_stride], rax
    mov eax, [r14 + Buffer.width]
    mov [rsp + R_JOB + UgfxScale_src_w], eax
    mov eax, [r14 + Buffer.height]
    mov [rsp + R_JOB + UgfxScale_src_h], eax
    mov r15d, [rsp + R_TOP]             ; the row
.row:
    mov eax, r15d
    sub eax, [rsp + R_TOP]
    cmp eax, [rsp + R_ROWS]
    jge .done
    mov eax, r15d
    sub eax, [rsp + R_SY]
    mov [rsp + R_JOB + UgfxScale_y], eax
    lea rdi, [rsp + R_JOB]
    call scale_bilinear_rect
    movsxd rdi, r15d                    ; into the frame
    imul rdi, [rbx + FrameCtx.stride]
    movsxd rax, dword [rsp + R_LEFT]
    lea rdi, [rdi + rax * 4]
    add rdi, [rbx + FrameCtx.framebuffer]
    lea rsi, [rel scale_row]
    mov edx, [rsp + R_WIDTH]
    cmp qword [rsp + R_NO_ALPHA], 0
    jne .copy
    call blend_over_premul
    jmp .next
.copy:
    shl rdx, 2
    call memcopy
.next:
    inc r15d
    jmp .row
.done:
    add rsp, UgfxScale_SIZE + 40
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15

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
    cmp dword [rdi + FrameCtx.px_scale], 0
    je .filled_here
    push rbx                            ; in pixels: mapped first
    sub rsp, 16
    mov ebx, edx
    mov rdx, rsp
    call frame_clip_rect
    test eax, eax
    jnz .mapped_out
    mov rsi, rsp
    mov edx, ebx
    call .filled_here
.mapped_out:
    add rsp, 16
    pop rbx
    xor eax, eax
    ret
.filled_here:
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

section .bss
alignb 16
scale_row:      resd SCALE_ROW_PX        ; render_scaled's one row

section .data
global sw_render_version
sw_render_version: dq 0x010100
