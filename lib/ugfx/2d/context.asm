; =============================================================================
; Utkarsha OS — lib/ugfx/2d/context.asm
; =============================================================================
; Drawing context: the state a 2D drawing API keeps between calls, and the
; draw calls that use it.
;
; State (saved and restored as a whole, up to UGFX_CTX_MAX_DEPTH deep):
;   transform        user space -> device space
;   clip             a mask; ugfx_ctx_clip intersects it with a path
;   fill, stroke     paints (solid colour, gradient, image), each with a
;                    matrix from paint space to user space
;   stroke style, dash, global alpha, fill rule, tolerance
;   target           the context's PixBuf, or a layer's
;
; Draw calls: fill, stroke, clip (paths in user space), fill_rect,
; stroke_rect, draw_image, clear. Strokes and dashes are built in user
; space and then transformed, so a non-uniform scale widens them the way
; HTML canvas does; their flattening tolerance is the device tolerance
; divided by sqrt|det|.
;
; Clips: each save depth owns at most one mask from a pool (plus one
; scratch mask), so memory stays bounded however often clip is called.
; A new clip is rendered with the current clip applied, which is the
; intersection. A union clip (SVG clipPath: shapes with their own
; transforms and rules) is built between ugfx_ctx_clip_begin and
; ugfx_ctx_clip_end: each ugfx_ctx_clip_add renders a path into a union
; mask (c + m (255 - c) / 255), and clip_end intersects the clip with it.
;
; Layers: ugfx_ctx_begin_layer(alpha) saves the state and redirects
; drawing into a transparent offscreen buffer the size of the target, with
; no clip and full alpha; ugfx_ctx_end_layer restores and composites the
; layer once, at alpha x the restored global alpha, under the restored clip
; (group opacity, without double-counting clip edges).
;
; Masks: inside a layer, ugfx_ctx_begin_mask opens another layer for the
; mask's content; ugfx_ctx_end_mask(mode) turns it into a coverage mask
; (luminance x alpha, or alpha) for the layer below, which end_layer then
; composites through (the mask times the restored clip).
;
; All storage comes from the arena given to ugfx_ctx_init.
; =============================================================================

%include "ugfx.inc"

extern arena_alloc
extern pixbuf_create
extern ugfx_raster_init
extern ugfx_raster_reset
extern ugfx_raster_set_clip
extern ugfx_raster_set_alpha
extern ugfx_raster_fill_paint
extern ugfx_raster_fill_mask
extern ugfx_path_init
extern ugfx_path_reset
extern ugfx_path_rasterize
extern ugfx_path_stroke
extern ugfx_path_dash
extern ugfx_path_add_rect
extern ugfx_paint_solid
extern ugfx_paint_image
extern ugfx_paint_set_transform
extern ugfx_mask_init
extern ugfx_mask_fill
extern ugfx_mask_copy
extern ugfx_mask_intersect
extern ugfx_mask_from_luminance
extern ugfx_mask_from_alpha
extern umath_affine2_identity
extern umath_affine2_multiply
extern umath_affine2_translate
extern umath_affine2_scale
extern umath_affine2_rotate
extern umath_affine2_determinant

%define CTX_STATE   UgfxContext_state
%define ST(f)       (UgfxContext_state + UgfxState_ %+ f)

section .rodata
align 8
ctx_default_tol:    dq UGFX_PATH_TOLERANCE
ctx_one:            dq 1.0
ctx_ten:            dq 10.0
ctx_zero:           dq 0.0

section .text

; -----------------------------------------------------------------------------
; ugfx_ctx_init — rdi = UgfxContext*, rsi = arena, rdx = target PixBuf*
;   -> rax = 0, -EINVAL, -ENOMEM
; -----------------------------------------------------------------------------
global ugfx_ctx_init
ugfx_ctx_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov rax, -(EINVAL)
    test rdi, rdi
    jz .init_out
    test rsi, rsi
    jz .init_out
    test rdx, rdx
    jz .init_out
    cmp qword [rdx + PixBuf_data], 0
    je .init_out
    mov [rbx + UgfxContext_arena], rsi
    mov [rbx + UgfxContext_root], rdx
    mov dword [rbx + UgfxContext_depth], 0
    mov dword [rbx + UgfxContext_union], 0
    lea rdi, [rbx + UgfxContext_raster]
    mov rcx, [rdx + PixBuf_height]
    mov rdx, [rdx + PixBuf_width]
    call ugfx_raster_init
    test rax, rax
    jnz .init_out
    lea rdi, [rbx + UgfxContext_path_a]
    mov rsi, [rbx + UgfxContext_arena]
    call ugfx_path_init
    test rax, rax
    jnz .init_out
    lea rdi, [rbx + UgfxContext_path_b]
    mov rsi, [rbx + UgfxContext_arena]
    call ugfx_path_init
    test rax, rax
    jnz .init_out
    lea rdi, [rbx + UgfxContext_path_c]
    mov rsi, [rbx + UgfxContext_arena]
    call ugfx_path_init
    test rax, rax
    jnz .init_out
    ; the state stack, the mask pool (one per depth + scratch), the layers
    mov esi, UGFX_CTX_MAX_DEPTH * UgfxState_SIZE
    call ctx_alloc_zero
    jz .init_nomem
    mov [rbx + UgfxContext_stack], rax
    mov esi, (UGFX_CTX_MAX_DEPTH + 3) * UgfxMask_SIZE
    call ctx_alloc_zero
    jz .init_nomem
    mov [rbx + UgfxContext_masks], rax
    mov esi, (UGFX_CTX_MAX_DEPTH + 1) * 8
    call ctx_alloc_zero
    jz .init_nomem
    mov [rbx + UgfxContext_layers], rax
    mov esi, (UGFX_CTX_MAX_DEPTH + 1) * UgfxMask_SIZE
    call ctx_alloc_zero
    jz .init_nomem
    mov [rbx + UgfxContext_lmasks], rax
    ; the default state
    mov qword [rbx + ST(mask)], 0
    lea rdi, [rbx + ST(transform)]
    call umath_affine2_identity
    movsd xmm0, [rel ctx_default_tol]
    movsd [rbx + ST(tolerance)], xmm0
    mov qword [rbx + ST(clip)], 0
    mov dword [rbx + ST(clip_owned)], 0
    mov dword [rbx + ST(rule)], UGFX_FILL_NONZERO
    mov dword [rbx + ST(alpha)], 255
    mov dword [rbx + ST(is_layer)], 0
    mov dword [rbx + ST(layer_alpha)], 255
    mov rax, [rbx + UgfxContext_root]
    mov [rbx + ST(target)], rax
    lea rdi, [rbx + ST(fill_paint)]
    mov esi, 0xFF000000
    call ugfx_paint_solid
    lea rdi, [rbx + ST(fill_matrix)]
    call umath_affine2_identity
    lea rdi, [rbx + ST(stroke_paint)]
    mov esi, 0xFF000000
    call ugfx_paint_solid
    lea rdi, [rbx + ST(stroke_matrix)]
    call umath_affine2_identity
    movsd xmm0, [rel ctx_one]
    movsd [rbx + ST(stroke) + UgfxStroke_width], xmm0
    movsd xmm0, [rel ctx_ten]
    movsd [rbx + ST(stroke) + UgfxStroke_miter_limit], xmm0
    mov dword [rbx + ST(stroke) + UgfxStroke_join], UGFX_JOIN_MITER
    mov dword [rbx + ST(stroke) + UgfxStroke_cap], UGFX_CAP_BUTT
    mov qword [rbx + ST(dash) + UgfxDash_intervals], 0
    mov dword [rbx + ST(dash) + UgfxDash_count], 0
    xor eax, eax
    jmp .init_out
.init_nomem:
    mov rax, -(ENOMEM)
.init_out:
    EPILOGUE_RESTORE rbx, r12

; esi = bytes -> rax = zeroed block from the context's arena (rbx), ZF set
;   when out of memory
ctx_alloc_zero:
    push rsi
    mov rdi, [rbx + UgfxContext_arena]
    call arena_alloc
    pop rcx
    test rax, rax
    jz .az_done
    mov rdi, rax
    mov rdx, rax
    xor eax, eax
    rep stosb
    mov rax, rdx
    test rax, rax
.az_done:
    ret

; -----------------------------------------------------------------------------
; ugfx_ctx_save / ugfx_ctx_restore — rdi = UgfxContext*
;   -> rax = 0, -EINVAL (stack full / empty)
; -----------------------------------------------------------------------------
global ugfx_ctx_save
ugfx_ctx_save:
    test rdi, rdi
    jz ctx_bad
    mov eax, [rdi + UgfxContext_depth]
    cmp eax, UGFX_CTX_MAX_DEPTH
    jae ctx_bad
    push rdi
    imul rax, rax, UgfxState_SIZE
    add rax, [rdi + UgfxContext_stack]
    lea rsi, [rdi + CTX_STATE]
    mov rdi, rax
    mov ecx, UgfxState_SIZE
    rep movsb
    pop rdi
    inc dword [rdi + UgfxContext_depth]
    mov dword [rdi + ST(clip_owned)], 0         ; the clip still belongs below
    mov dword [rdi + ST(is_layer)], 0
    xor eax, eax
    ret

global ugfx_ctx_restore
ugfx_ctx_restore:
    test rdi, rdi
    jz ctx_bad
    mov eax, [rdi + UgfxContext_depth]
    test eax, eax
    jz ctx_bad
    dec eax
    mov [rdi + UgfxContext_depth], eax
    imul rax, rax, UgfxState_SIZE
    add rax, [rdi + UgfxContext_stack]
    mov rsi, rax
    lea rdi, [rdi + CTX_STATE]
    mov ecx, UgfxState_SIZE
    rep movsb
    xor eax, eax
    ret

ctx_bad:
    mov rax, -(EINVAL)
    ret

; -----------------------------------------------------------------------------
; Transform: ugfx_ctx_set_transform(ctx, m), ugfx_ctx_transform(ctx, m)
;   (m applied first, then the current transform), ugfx_ctx_translate(ctx,
;   tx, ty), ugfx_ctx_scale(ctx, sx, sy), ugfx_ctx_rotate(ctx, radians)
; -----------------------------------------------------------------------------
global ugfx_ctx_set_transform
ugfx_ctx_set_transform:
    test rdi, rdi
    jz ctx_bad
    test rsi, rsi
    jz ctx_bad
    lea rdi, [rdi + ST(transform)]
    mov ecx, 48
    rep movsb
    xor eax, eax
    ret

global ugfx_ctx_transform
ugfx_ctx_transform:
    test rdi, rdi
    jz ctx_bad
    test rsi, rsi
    jz ctx_bad
    mov rdx, rsi
    lea rdi, [rdi + ST(transform)]
    mov rsi, rdi
    sub rsp, 8
    call umath_affine2_multiply
    add rsp, 8
    xor eax, eax
    ret

global ugfx_ctx_translate
ugfx_ctx_translate:
    lea rax, [rel umath_affine2_translate]
    jmp ctx_compose
global ugfx_ctx_scale
ugfx_ctx_scale:
    lea rax, [rel umath_affine2_scale]
    jmp ctx_compose
global ugfx_ctx_rotate
ugfx_ctx_rotate:
    lea rax, [rel umath_affine2_rotate]

; rdi = ctx, rax = umath builder (out, xmm0, xmm1) -> transform = transform x m
ctx_compose:
    test rdi, rdi
    jz ctx_bad
    push rbx
    mov rbx, rdi
    lea rdi, [rbx + UgfxContext_tmp_m2]
    call rax
    lea rdi, [rbx + ST(transform)]
    mov rsi, rdi
    lea rdx, [rbx + UgfxContext_tmp_m2]
    call umath_affine2_multiply
    pop rbx
    xor eax, eax
    ret

; -----------------------------------------------------------------------------
; Paint and style:
;   ugfx_ctx_set_fill_color(ctx, colour)    premultiplied BGRA
;   ugfx_ctx_set_fill_paint(ctx, paint, m)  copied; m = paint -> user space
;                                           (0: identity)
;   ugfx_ctx_set_stroke_color / ugfx_ctx_set_stroke_paint (the same)
;   ugfx_ctx_set_stroke_style(ctx, style)   copied
;   ugfx_ctx_set_dash(ctx, dash)            copied (intervals by reference);
;                                           0 = solid lines
;   ugfx_ctx_set_alpha(ctx, 0..255), ugfx_ctx_set_fill_rule(ctx, rule),
;   ugfx_ctx_set_tolerance(ctx, device pixels; <= 0 or NaN: default)
; -----------------------------------------------------------------------------
global ugfx_ctx_set_fill_color
ugfx_ctx_set_fill_color:
    mov edx, UgfxState_fill_paint
    jmp ctx_set_color
global ugfx_ctx_set_stroke_color
ugfx_ctx_set_stroke_color:
    mov edx, UgfxState_stroke_paint

; rdi = ctx, esi = colour, edx = paint offset in the state (matrix follows it)
ctx_set_color:
    test rdi, rdi
    jz ctx_bad
    push rbx
    lea rbx, [rdi + CTX_STATE + rdx]
    mov rdi, rbx
    call ugfx_paint_solid
    lea rdi, [rbx + UgfxPaint_SIZE]
    call umath_affine2_identity
    pop rbx
    xor eax, eax
    ret

global ugfx_ctx_set_fill_paint
ugfx_ctx_set_fill_paint:
    mov ecx, UgfxState_fill_paint
    jmp ctx_set_paint
global ugfx_ctx_set_stroke_paint
ugfx_ctx_set_stroke_paint:
    mov ecx, UgfxState_stroke_paint

; rdi = ctx, rsi = paint, rdx = matrix or 0, ecx = paint offset
ctx_set_paint:
    test rdi, rdi
    jz ctx_bad
    test rsi, rsi
    jz ctx_bad
    cmp qword [rsi + UgfxPaint_span], 0
    je ctx_bad
    push rbx
    lea rbx, [rdi + CTX_STATE + rcx]
    mov rdi, rbx
    mov ecx, UgfxPaint_SIZE
    rep movsb
    lea rdi, [rbx + UgfxPaint_SIZE]
    test rdx, rdx
    jz .sp_identity
    mov rsi, rdx
    mov ecx, 48
    rep movsb
    jmp .sp_done
.sp_identity:
    call umath_affine2_identity
.sp_done:
    pop rbx
    xor eax, eax
    ret

global ugfx_ctx_set_stroke_style
ugfx_ctx_set_stroke_style:
    test rdi, rdi
    jz ctx_bad
    test rsi, rsi
    jz ctx_bad
    lea rdi, [rdi + ST(stroke)]
    mov ecx, UgfxStroke_SIZE
    rep movsb
    xor eax, eax
    ret

global ugfx_ctx_set_dash
ugfx_ctx_set_dash:
    test rdi, rdi
    jz ctx_bad
    lea rdi, [rdi + ST(dash)]
    test rsi, rsi
    jz .dash_off
    mov ecx, UgfxDash_SIZE
    rep movsb
    xor eax, eax
    ret
.dash_off:
    mov qword [rdi + UgfxDash_intervals], 0
    mov dword [rdi + UgfxDash_count], 0
    xor eax, eax
    ret

global ugfx_ctx_set_alpha
ugfx_ctx_set_alpha:
    test rdi, rdi
    jz ctx_bad
    cmp esi, 255
    ja ctx_bad
    mov [rdi + ST(alpha)], esi
    xor eax, eax
    ret

global ugfx_ctx_set_fill_rule
ugfx_ctx_set_fill_rule:
    test rdi, rdi
    jz ctx_bad
    cmp esi, UGFX_FILL_EVENODD
    ja ctx_bad
    mov [rdi + ST(rule)], esi
    xor eax, eax
    ret

global ugfx_ctx_set_tolerance
ugfx_ctx_set_tolerance:
    test rdi, rdi
    jz ctx_bad
    xorpd xmm1, xmm1
    ucomisd xmm0, xmm1
    jp .tol_default
    ja .tol_set
.tol_default:
    movsd xmm0, [rel ctx_default_tol]
.tol_set:
    movsd [rdi + ST(tolerance)], xmm0
    xor eax, eax
    ret

; -----------------------------------------------------------------------------
; ugfx_ctx_fill — rdi = ctx, rsi = UgfxPath* (user space) -> rax = 0, -errno
; ugfx_ctx_stroke — the same, outlined with the stroke style (and dash)
; ugfx_ctx_clip — intersect the clip with the path (fill rule applies)
; -----------------------------------------------------------------------------
global ugfx_ctx_fill
ugfx_ctx_fill:
    test rdi, rdi
    jz ctx_bad
    test rsi, rsi
    jz ctx_bad
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov rdi, rsi
    call ctx_rasterize
    test rax, rax
    jnz .fill_out
    mov esi, UgfxState_fill_paint
    mov edx, [rbx + ST(rule)]
    call ctx_paint_fill
.fill_out:
    EPILOGUE_RESTORE rbx, r12

global ugfx_ctx_stroke
ugfx_ctx_stroke:
    test rdi, rdi
    jz ctx_bad
    test rsi, rsi
    jz ctx_bad
    PROLOGUE_SAVE rbx, r12
    sub rsp, 16
    mov rbx, rdi
    mov r12, rsi
    ; user-space tolerance = tolerance / sqrt|det|; a flat transform draws nothing
    lea rdi, [rbx + ST(transform)]
    call umath_affine2_determinant
    andpd xmm0, [rel ctx_abs_mask]
    sqrtsd xmm0, xmm0
    xorpd xmm1, xmm1
    ucomisd xmm0, xmm1
    jp .stroke_none
    je .stroke_none
    movsd xmm1, [rbx + ST(tolerance)]
    divsd xmm1, xmm0
    movsd [rsp], xmm1
    cmp qword [rbx + ST(dash) + UgfxDash_intervals], 0
    je .stroke_solid
    lea rdi, [rbx + UgfxContext_path_a]
    call ugfx_path_reset
    lea rdi, [rbx + UgfxContext_path_a]
    mov rsi, r12
    lea rdx, [rbx + ST(dash)]
    movsd xmm0, [rsp]
    call ugfx_path_dash
    test rax, rax
    jnz .stroke_out
    lea r12, [rbx + UgfxContext_path_a]
.stroke_solid:
    lea rdi, [rbx + UgfxContext_path_b]
    call ugfx_path_reset
    lea rdi, [rbx + UgfxContext_path_b]
    mov rsi, r12
    lea rdx, [rbx + ST(stroke)]
    movsd xmm0, [rsp]
    call ugfx_path_stroke
    test rax, rax
    jnz .stroke_out
    lea rdi, [rbx + UgfxContext_path_b]
    call ctx_rasterize
    test rax, rax
    jnz .stroke_out
    mov esi, UgfxState_stroke_paint
    mov edx, UGFX_FILL_NONZERO
    call ctx_paint_fill
    jmp .stroke_out
.stroke_none:
    xor eax, eax
.stroke_out:
    add rsp, 16
    EPILOGUE_RESTORE rbx, r12

global ugfx_ctx_clip
ugfx_ctx_clip:
    test rdi, rdi
    jz ctx_bad
    test rsi, rsi
    jz ctx_bad
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov rdi, rsi
    call ctx_rasterize
    test rax, rax
    jnz .clip_out
    ; the mask to render into: this depth's own, or scratch if already owned
    mov eax, [rbx + UgfxContext_depth]
    cmp dword [rbx + ST(clip_owned)], 0
    je .clip_have_index
    mov eax, UGFX_CTX_MAX_DEPTH + 1
.clip_have_index:
    call ctx_mask
    test rax, rax
    jz .clip_nomem
    mov r12, rax
    mov rdi, r12
    xor esi, esi
    call ugfx_mask_fill
    ; rendered under the current clip: the intersection
    lea rdi, [rbx + UgfxContext_raster]
    mov rsi, [rbx + ST(clip)]
    call ugfx_raster_set_clip
    lea rdi, [rbx + UgfxContext_raster]
    mov esi, 255
    call ugfx_raster_set_alpha
    lea rdi, [rbx + UgfxContext_raster]
    mov rsi, r12
    mov ecx, [rbx + ST(rule)]
    call ugfx_raster_fill_mask
    test rax, rax
    jnz .clip_out
    cmp dword [rbx + ST(clip_owned)], 0
    je .clip_take
    mov rdi, [rbx + ST(clip)]           ; owned: scratch -> own mask
    mov rsi, r12
    call ugfx_mask_copy
    jmp .clip_ok
.clip_take:
    mov [rbx + ST(clip)], r12
    mov dword [rbx + ST(clip_owned)], 1
.clip_ok:
    xor eax, eax
    jmp .clip_out
.clip_nomem:
    lea rdi, [rbx + UgfxContext_raster]
    call ugfx_raster_reset
    mov rax, -(ENOMEM)
.clip_out:
    EPILOGUE_RESTORE rbx, r12

; -----------------------------------------------------------------------------
; ugfx_ctx_clip_begin — rdi = ctx -> rax = 0, -EINVAL (one already open),
;   -ENOMEM: an empty union clip
; ugfx_ctx_clip_add — rdi = ctx, rsi = UgfxPath* -> rax = 0, -EINVAL (none
;   open), -errno: the path (current transform and fill rule) added
; ugfx_ctx_clip_end — rdi = ctx -> rax = 0, -EINVAL (none open): the clip
;   becomes its intersection with the union
; -----------------------------------------------------------------------------
global ugfx_ctx_clip_begin
ugfx_ctx_clip_begin:
    test rdi, rdi
    jz ctx_bad
    cmp dword [rdi + UgfxContext_union], 0
    jne ctx_bad
    push rbx
    mov rbx, rdi
    mov eax, UGFX_CTX_MAX_DEPTH + 2
    call ctx_mask
    test rax, rax
    jz .cb_nomem
    mov rdi, rax
    xor esi, esi
    call ugfx_mask_fill
    mov dword [rbx + UgfxContext_union], 1
    xor eax, eax
    pop rbx
    ret
.cb_nomem:
    mov rax, -(ENOMEM)
    pop rbx
    ret

global ugfx_ctx_clip_add
ugfx_ctx_clip_add:
    test rdi, rdi
    jz ctx_bad
    test rsi, rsi
    jz ctx_bad
    cmp dword [rdi + UgfxContext_union], 0
    je ctx_bad
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov rdi, rsi
    call ctx_rasterize
    test rax, rax
    jnz .ca_out
    lea rdi, [rbx + UgfxContext_raster]
    xor esi, esi                        ; no clip: intersected at the end
    call ugfx_raster_set_clip
    lea rdi, [rbx + UgfxContext_raster]
    mov esi, 255
    call ugfx_raster_set_alpha
    mov eax, UGFX_CTX_MAX_DEPTH + 2
    call ctx_mask
    lea rdi, [rbx + UgfxContext_raster]
    mov rsi, rax
    mov ecx, [rbx + ST(rule)]
    call ugfx_raster_fill_mask
.ca_out:
    EPILOGUE_RESTORE rbx, r12

global ugfx_ctx_clip_end
ugfx_ctx_clip_end:
    test rdi, rdi
    jz ctx_bad
    cmp dword [rdi + UgfxContext_union], 0
    je ctx_bad
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov dword [rbx + UgfxContext_union], 0
    mov eax, UGFX_CTX_MAX_DEPTH + 2
    call ctx_mask
    mov r12, rax                        ; the union
    cmp dword [rbx + ST(clip_owned)], 0
    je .ce_own
    mov rdi, [rbx + ST(clip)]           ; this depth's mask: intersect in place
    mov rsi, r12
    call ugfx_mask_intersect
    jmp .ce_ok
.ce_own:
    mov eax, [rbx + UgfxContext_depth]
    call ctx_mask
    test rax, rax
    jz .ce_nomem
    push rax
    sub rsp, 8
    mov rdi, rax
    mov rsi, r12
    call ugfx_mask_copy
    add rsp, 8
    pop rdi
    mov rsi, [rbx + ST(clip)]
    mov [rbx + ST(clip)], rdi
    mov dword [rbx + ST(clip_owned)], 1
    test rsi, rsi
    jz .ce_ok
    call ugfx_mask_intersect            ; with the clip it had
.ce_ok:
    xor eax, eax
    jmp .ce_out
.ce_nomem:
    mov rax, -(ENOMEM)
.ce_out:
    EPILOGUE_RESTORE rbx, r12

; eax = pool index, rbx = ctx -> rax = UgfxMask* (initialised), 0 = no memory
ctx_mask:
    push r12
    imul eax, eax, UgfxMask_SIZE
    mov r12, [rbx + UgfxContext_masks]
    add r12, rax
    cmp qword [r12 + UgfxMask_data], 0
    jne .mask_ready
    mov rdi, r12
    mov rsi, [rbx + UgfxContext_arena]
    mov rax, [rbx + UgfxContext_root]
    mov rdx, [rax + PixBuf_width]
    mov rcx, [rax + PixBuf_height]
    call ugfx_mask_init
    test rax, rax
    jz .mask_ready
    xor eax, eax
    pop r12
    ret
.mask_ready:
    mov rax, r12
    pop r12
    ret

; rdi = path, rbx = ctx -> rax = 0 / -errno; the raster holds the path in
;   device space
ctx_rasterize:
    sub rsp, 8
    lea rsi, [rbx + UgfxContext_raster]
    lea rdx, [rbx + ST(transform)]
    movsd xmm0, [rbx + ST(tolerance)]
    call ugfx_path_rasterize
    add rsp, 8
    ret

; rbx = ctx, esi = paint offset in the state (its matrix follows),
;   edx = rule -> fills the rasterized path with that paint
ctx_paint_fill:
    push r12
    push r13
    sub rsp, 8
    lea r12, [rbx + CTX_STATE + rsi]
    mov r13d, edx
    ; device <- user <- paint
    lea rdi, [rbx + UgfxContext_tmp_m]
    lea rsi, [rbx + ST(transform)]
    lea rdx, [r12 + UgfxPaint_SIZE]
    call umath_affine2_multiply
    lea rdi, [rbx + UgfxContext_tmp_paint]
    mov rsi, r12
    mov ecx, UgfxPaint_SIZE
    rep movsb
    lea rdi, [rbx + UgfxContext_tmp_paint]
    mov esi, r13d
    call ctx_fill_placed
    add rsp, 8
    pop r13
    pop r12
    ret

; rbx = ctx, rdi = paint (writable), esi = rule: places the paint with the
;   device matrix in tmp_m and fills the rasterized path with the state's
;   clip and alpha into its target. A paint that cannot be placed (flat
;   transform) draws nothing.
ctx_fill_placed:
    push r12
    push r13
    sub rsp, 8
    mov r12, rdi
    mov r13d, esi
    mov rdi, r12
    lea rsi, [rbx + UgfxContext_tmp_m]
    call ugfx_paint_set_transform
    test rax, rax
    jnz .pf_nothing
    lea rdi, [rbx + UgfxContext_raster]
    mov rsi, [rbx + ST(clip)]
    call ugfx_raster_set_clip
    lea rdi, [rbx + UgfxContext_raster]
    mov esi, [rbx + ST(alpha)]
    call ugfx_raster_set_alpha
    lea rdi, [rbx + UgfxContext_raster]
    mov rsi, [rbx + ST(target)]
    mov rdx, r12
    mov ecx, r13d
    call ugfx_raster_fill_paint
    jmp .pf_out
.pf_nothing:
    lea rdi, [rbx + UgfxContext_raster]
    call ugfx_raster_reset
    xor eax, eax
.pf_out:
    add rsp, 8
    pop r13
    pop r12
    ret

; -----------------------------------------------------------------------------
; ugfx_ctx_fill_rect / ugfx_ctx_stroke_rect — rdi = ctx, xmm0..xmm3 = x, y,
;   w, h (user space) -> rax = 0, -errno
; -----------------------------------------------------------------------------
global ugfx_ctx_fill_rect
ugfx_ctx_fill_rect:
    lea rax, [rel ugfx_ctx_fill]
    jmp ctx_rect
global ugfx_ctx_stroke_rect
ugfx_ctx_stroke_rect:
    lea rax, [rel ugfx_ctx_stroke]

ctx_rect:
    test rdi, rdi
    jz ctx_bad
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    mov r12, rax
    sub rsp, 32
    movsd [rsp], xmm0
    movsd [rsp + 8], xmm1
    movsd [rsp + 16], xmm2
    movsd [rsp + 24], xmm3
    lea rdi, [rbx + UgfxContext_path_c]
    call ugfx_path_reset
    lea rdi, [rbx + UgfxContext_path_c]
    movsd xmm0, [rsp]
    movsd xmm1, [rsp + 8]
    movsd xmm2, [rsp + 16]
    movsd xmm3, [rsp + 24]
    call ugfx_path_add_rect
    add rsp, 32
    test rax, rax
    jnz .rect_out
    mov rdi, rbx
    lea rsi, [rbx + UgfxContext_path_c]
    call r12
.rect_out:
    add rsp, 8
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ugfx_ctx_draw_image — rdi = ctx, rsi = const PixBuf* (premultiplied BGRA),
;   xmm0..xmm3 = x, y, w, h: the image scaled into that rectangle (user
;   space), bilinear, edges clamped -> rax = 0, -errno
; -----------------------------------------------------------------------------
global ugfx_ctx_draw_image
ugfx_ctx_draw_image:
    test rdi, rdi
    jz ctx_bad
    test rsi, rsi
    jz ctx_bad
    PROLOGUE_SAVE rbx, r12, r13, r14
    sub rsp, 32
    mov rbx, rdi
    mov r14, rsi
    movsd [rsp], xmm0
    movsd [rsp + 8], xmm1
    movsd [rsp + 16], xmm2
    movsd [rsp + 24], xmm3
    lea rdi, [rbx + UgfxContext_tmp_paint]
    mov rsi, r14
    mov edx, UGFX_SPREAD_PAD
    mov ecx, UGFX_SPREAD_PAD
    mov r8d, UGFX_FILTER_BILINEAR
    call ugfx_paint_image
    test rax, rax
    jnz .di_out
    ; paint -> user: scale (w / iw, h / ih), then translate (x, y)
    lea rax, [rbx + UgfxContext_tmp_m2]
    movsd xmm0, [rsp + 16]
    cvtsi2sd xmm1, qword [r14 + PixBuf_width]
    divsd xmm0, xmm1
    movsd [rax], xmm0
    xorpd xmm0, xmm0
    movsd [rax + 8], xmm0
    movsd [rax + 16], xmm0
    movsd xmm0, [rsp + 24]
    cvtsi2sd xmm1, qword [r14 + PixBuf_height]
    divsd xmm0, xmm1
    movsd [rax + 24], xmm0
    movsd xmm0, [rsp]
    movsd [rax + 32], xmm0
    movsd xmm0, [rsp + 8]
    movsd [rax + 40], xmm0
    lea rdi, [rbx + UgfxContext_tmp_m]
    lea rsi, [rbx + ST(transform)]
    lea rdx, [rbx + UgfxContext_tmp_m2]
    call umath_affine2_multiply
    ; the rectangle
    lea rdi, [rbx + UgfxContext_path_c]
    call ugfx_path_reset
    lea rdi, [rbx + UgfxContext_path_c]
    movsd xmm0, [rsp]
    movsd xmm1, [rsp + 8]
    movsd xmm2, [rsp + 16]
    movsd xmm3, [rsp + 24]
    call ugfx_path_add_rect
    test rax, rax
    jnz .di_out
    lea rdi, [rbx + UgfxContext_path_c]
    call ctx_rasterize
    test rax, rax
    jnz .di_out
    lea rdi, [rbx + UgfxContext_tmp_paint]
    mov esi, UGFX_FILL_NONZERO
    call ctx_fill_placed
.di_out:
    add rsp, 32
    EPILOGUE_RESTORE rbx, r12, r13, r14

; -----------------------------------------------------------------------------
; ugfx_ctx_clear — rdi = ctx, esi = colour: every pixel of the current target
;   (ignores transform, clip and alpha) -> rax = 0, -EINVAL
; -----------------------------------------------------------------------------
global ugfx_ctx_clear
ugfx_ctx_clear:
    test rdi, rdi
    jz ctx_bad
    mov r8, [rdi + ST(target)]
    mov eax, esi
    xor r9d, r9d
.clear_row:
    cmp r9, [r8 + PixBuf_height]
    jae .clear_done
    mov rdi, r9
    imul rdi, [r8 + PixBuf_stride]
    add rdi, [r8 + PixBuf_data]
    mov rcx, [r8 + PixBuf_width]
    rep stosd
    inc r9
    jmp .clear_row
.clear_done:
    xor eax, eax
    ret

; -----------------------------------------------------------------------------
; ugfx_ctx_begin_layer — rdi = ctx, esi = alpha 0..255 -> rax = 0, -errno
; ugfx_ctx_end_layer — rdi = ctx -> rax = 0, -EINVAL (no layer open), -errno
; -----------------------------------------------------------------------------
global ugfx_ctx_begin_layer
ugfx_ctx_begin_layer:
    test rdi, rdi
    jz ctx_bad
    cmp esi, 255
    ja ctx_bad
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12d, esi
    call ugfx_ctx_save
    test rax, rax
    jnz .bl_out
    ; this depth's layer buffer, created once
    mov eax, [rbx + UgfxContext_depth]
    mov rcx, [rbx + UgfxContext_layers]
    lea rcx, [rcx + rax * 8]
    mov rax, [rcx]
    test rax, rax
    jnz .bl_have
    push rcx
    sub rsp, 8
    mov rax, [rbx + UgfxContext_root]
    mov rdi, [rbx + UgfxContext_arena]
    mov rsi, [rax + PixBuf_width]
    mov rdx, [rax + PixBuf_height]
    mov rcx, [rax + PixBuf_format]
    call pixbuf_create
    add rsp, 8
    pop rcx
    test rax, rax
    jle .bl_nomem
    mov [rcx], rax
.bl_have:
    mov [rbx + ST(target)], rax
    mov dword [rbx + ST(is_layer)], 1
    mov qword [rbx + ST(mask)], 0
    mov [rbx + ST(layer_alpha)], r12d
    mov dword [rbx + ST(alpha)], 255
    mov qword [rbx + ST(clip)], 0
    mov dword [rbx + ST(clip_owned)], 0
    mov rdi, rbx
    xor esi, esi
    call ugfx_ctx_clear
    xor eax, eax
    jmp .bl_out
.bl_nomem:
    mov rdi, rbx
    call ugfx_ctx_restore
    mov rax, -(ENOMEM)
.bl_out:
    EPILOGUE_RESTORE rbx, r12

global ugfx_ctx_end_layer
ugfx_ctx_end_layer:
    test rdi, rdi
    jz ctx_bad
    cmp dword [rdi + ST(is_layer)], 1
    jne ctx_bad
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r14, [rbx + ST(target)]         ; the layer
    mov r12d, [rbx + ST(layer_alpha)]
    mov r15, [rbx + ST(mask)]
    call ugfx_ctx_restore
    ; a mask: composited through it times the restored clip
    test r15, r15
    jz .el_clip
    mov rax, [rbx + ST(clip)]
    test rax, rax
    jz .el_masked
    mov eax, UGFX_CTX_MAX_DEPTH + 1
    call ctx_mask
    test rax, rax
    jz .el_nomem
    push rax
    sub rsp, 8
    mov rdi, rax
    mov rsi, r15
    call ugfx_mask_copy
    mov rdi, [rsp + 8]
    mov rsi, [rbx + ST(clip)]
    call ugfx_mask_intersect
    add rsp, 8
    pop r15
.el_masked:
    xchg r15, [rbx + ST(clip)]          ; r15 = the clip to put back
    jmp .el_alpha
.el_clip:
    mov r15, [rbx + ST(clip)]
.el_alpha:
    ; composite: alpha = layer alpha x restored alpha
    mov eax, [rbx + ST(alpha)]
    imul eax, r12d
    add eax, 128
    mov edx, eax
    shr edx, 8
    add eax, edx
    shr eax, 8
    mov r12d, eax
    lea rdi, [rbx + UgfxContext_tmp_paint]
    mov rsi, r14
    mov edx, UGFX_SPREAD_NONE
    mov ecx, UGFX_SPREAD_NONE
    mov r8d, UGFX_FILTER_NEAREST
    call ugfx_paint_image
    test rax, rax
    jnz .el_out
    lea rdi, [rbx + UgfxContext_tmp_m]
    call umath_affine2_identity
    ; the whole layer in device space
    lea rdi, [rbx + UgfxContext_path_c]
    call ugfx_path_reset
    lea rdi, [rbx + UgfxContext_path_c]
    xorpd xmm0, xmm0
    xorpd xmm1, xmm1
    cvtsi2sd xmm2, qword [r14 + PixBuf_width]
    cvtsi2sd xmm3, qword [r14 + PixBuf_height]
    call ugfx_path_add_rect
    test rax, rax
    jnz .el_out
    lea rdi, [rbx + UgfxContext_path_c]
    lea rsi, [rbx + UgfxContext_raster]
    xor edx, edx
    movsd xmm0, [rbx + ST(tolerance)]
    call ugfx_path_rasterize
    test rax, rax
    jnz .el_out
    ; ctx_fill_placed takes alpha from the state: use the product
    mov r13d, [rbx + ST(alpha)]
    mov [rbx + ST(alpha)], r12d
    lea rdi, [rbx + UgfxContext_tmp_paint]
    mov esi, UGFX_FILL_NONZERO
    call ctx_fill_placed
    mov [rbx + ST(alpha)], r13d
.el_out:
    mov [rbx + ST(clip)], r15
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
.el_nomem:
    mov rax, -(ENOMEM)
    mov r15, [rbx + ST(clip)]
    jmp .el_out

; -----------------------------------------------------------------------------
; ugfx_ctx_begin_mask — rdi = ctx -> rax = 0, -errno: a layer for a mask's
;   content (it ends with end_mask, not end_layer)
; ugfx_ctx_end_mask — rdi = ctx, esi = UGFX_MASK_LUMINANCE / _ALPHA
;   -> rax = 0, -EINVAL (no mask open), -ENOMEM: back to the state below,
;   whose layer will be composited through the mask
; -----------------------------------------------------------------------------
global ugfx_ctx_begin_mask
ugfx_ctx_begin_mask:
    test rdi, rdi
    jz ctx_bad
    push rbx
    mov rbx, rdi
    mov esi, 255
    call ugfx_ctx_begin_layer
    test rax, rax
    jnz .bm_out
    mov dword [rbx + ST(is_layer)], 2
.bm_out:
    pop rbx
    ret

global ugfx_ctx_end_mask
ugfx_ctx_end_mask:
    test rdi, rdi
    jz ctx_bad
    cmp dword [rdi + ST(is_layer)], 2
    jne ctx_bad
    cmp esi, UGFX_MASK_ALPHA
    ja ctx_bad
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12d, esi
    mov r13, [rbx + ST(target)]         ; the mask's content
    call ugfx_ctx_restore
    ; this depth's layer mask, created once
    mov eax, [rbx + UgfxContext_depth]
    imul eax, eax, UgfxMask_SIZE
    mov rdi, [rbx + UgfxContext_lmasks]
    add rdi, rax
    cmp qword [rdi + UgfxMask_data], 0
    jne .em_have
    push rdi
    sub rsp, 8
    mov rsi, [rbx + UgfxContext_arena]
    mov rax, [rbx + UgfxContext_root]
    mov rdx, [rax + PixBuf_width]
    mov rcx, [rax + PixBuf_height]
    call ugfx_mask_init
    add rsp, 8
    pop rdi
    test rax, rax
    jnz .em_out
.em_have:
    mov [rbx + ST(mask)], rdi
    mov rsi, r13
    test r12d, r12d
    jnz .em_alpha
    call ugfx_mask_from_luminance
    jmp .em_out
.em_alpha:
    call ugfx_mask_from_alpha
.em_out:
    EPILOGUE_RESTORE rbx, r12, r13

section .rodata
align 16
ctx_abs_mask:       dq 0x7FFFFFFFFFFFFFFF, 0x7FFFFFFFFFFFFFFF

section .data
global ugfx_context_version
ugfx_context_version: dq 0x010000
