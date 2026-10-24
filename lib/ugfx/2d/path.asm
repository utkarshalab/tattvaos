; =============================================================================
; Utkarsha OS — lib/ugfx/2d/path.asm
; =============================================================================
; Paths: contours of lines, quadratic and cubic Beziers in f64 user space.
;
;   ugfx_path_init / reset            storage from the caller's arena
;   ugfx_path_move_to / line_to / quad_to / cubic_to / close
;   ugfx_path_current                 the current point
;   ugfx_path_transform               apply an affine transform in place
;   ugfx_path_bounds                  control-point bounds (conservative)
;   ugfx_path_rasterize               flatten into a UgfxRaster
;
; Drawing without an open contour starts one at the current point. After
; close, the current point is the closed contour's start. Points are (x, y)
; in xmm registers, in order. Rasterizing transforms curves to device space
; first (affine maps preserve Beziers), then flattens each one into the
; number of equal-t segments that keeps it within the tolerance (Wang's
; formula, lib/umath/geom), so the error bound holds in device pixels.
; =============================================================================

%include "ugfx.inc"

extern arena_alloc
extern ugfx_raster_move_to
extern ugfx_raster_line_to
extern ugfx_raster_close
extern umath_affine2_apply
extern umath_affine2_apply_array
extern umath_bezier_quad_eval
extern umath_bezier_cubic_eval
extern umath_bezier_quad_segments
extern umath_bezier_cubic_segments

%define PATH_INITIAL_VERBS  64
%define PATH_INITIAL_POINTS 128

section .rodata
align 8
path_fix_scale:     dq 256.0
path_fix_max:       dq 1073741824.0
path_fix_min:       dq -1073741824.0
path_default_tol:   dq UGFX_PATH_TOLERANCE
path_huge:          dq 1.0e300
path_neg_huge:      dq -1.0e300

section .text

; -----------------------------------------------------------------------------
; ugfx_path_init — rdi = UgfxPath*, rsi = arena -> rax = 0, -EINVAL, -ENOMEM
; -----------------------------------------------------------------------------
global ugfx_path_init
ugfx_path_init:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    test rdi, rdi
    jz .init_bad
    test rsi, rsi
    jz .init_bad
    mov [rbx + UgfxPath_arena], rsi
    mov rdi, rsi
    mov esi, PATH_INITIAL_VERBS
    call arena_alloc
    test rax, rax
    jz .init_nomem
    mov [rbx + UgfxPath_verbs], rax
    mov dword [rbx + UgfxPath_verb_cap], PATH_INITIAL_VERBS
    mov rdi, [rbx + UgfxPath_arena]
    mov esi, PATH_INITIAL_POINTS * 16
    call arena_alloc
    test rax, rax
    jz .init_nomem
    mov [rbx + UgfxPath_points], rax
    mov dword [rbx + UgfxPath_point_cap], PATH_INITIAL_POINTS
    mov rdi, rbx
    call ugfx_path_reset
    xor eax, eax
    EPILOGUE_RESTORE rbx
.init_bad:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx
.init_nomem:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx

; -----------------------------------------------------------------------------
; ugfx_path_reset — rdi = UgfxPath*; empties the path, keeps the storage
; -----------------------------------------------------------------------------
global ugfx_path_reset
ugfx_path_reset:
    xor eax, eax
    mov [rdi + UgfxPath_verb_count], eax
    mov [rdi + UgfxPath_point_count], eax
    mov [rdi + UgfxPath_start], eax
    mov [rdi + UgfxPath_open], eax
    mov [rdi + UgfxPath_error], eax
    ret

; -----------------------------------------------------------------------------
; rbx = path, ecx = points needed -> eax = 0 or -ENOMEM (also one verb).
; Clobbers rax, rcx, rdx, rsi, rdi, r8-r11 and xmm8-xmm15 are preserved by
; arena_alloc's contract only for callee-saved state, so callers keep their
; coordinates on the stack.
; -----------------------------------------------------------------------------
path_reserve:
    push r12
    mov r12d, ecx
    cmp dword [rbx + UgfxPath_error], 0
    jne .reserve_fail
    mov eax, [rbx + UgfxPath_verb_count]
    cmp eax, [rbx + UgfxPath_verb_cap]
    jb .verbs_ok
    mov esi, [rbx + UgfxPath_verb_cap]
    add esi, esi
    mov rdi, [rbx + UgfxPath_arena]
    call arena_alloc
    test rax, rax
    jz .reserve_nomem
    mov rdi, rax
    mov rsi, [rbx + UgfxPath_verbs]
    mov ecx, [rbx + UgfxPath_verb_count]
    rep movsb
    mov [rbx + UgfxPath_verbs], rax
    shl dword [rbx + UgfxPath_verb_cap], 1
.verbs_ok:
    mov eax, [rbx + UgfxPath_point_count]
    add eax, r12d
    cmp eax, [rbx + UgfxPath_point_cap]
    jbe .points_ok
    mov esi, [rbx + UgfxPath_point_cap]
    add esi, esi
    shl rsi, 4
    mov rdi, [rbx + UgfxPath_arena]
    call arena_alloc
    test rax, rax
    jz .reserve_nomem
    mov rdi, rax
    mov rsi, [rbx + UgfxPath_points]
    mov ecx, [rbx + UgfxPath_point_count]
    shl rcx, 4
    rep movsb
    mov [rbx + UgfxPath_points], rax
    shl dword [rbx + UgfxPath_point_cap], 1
.points_ok:
    xor eax, eax
    pop r12
    ret
.reserve_nomem:
    mov dword [rbx + UgfxPath_error], 1
.reserve_fail:
    mov eax, -(ENOMEM)
    pop r12
    ret

; rbx = path, al = verb (capacity already reserved)
path_push_verb:
    mov ecx, [rbx + UgfxPath_verb_count]
    mov rdx, [rbx + UgfxPath_verbs]
    mov [rdx + rcx], al
    inc dword [rbx + UgfxPath_verb_count]
    ret

; rbx = path, xmm0/xmm1 = point (capacity already reserved)
path_push_point:
    mov ecx, [rbx + UgfxPath_point_count]
    shl rcx, 4
    add rcx, [rbx + UgfxPath_points]
    movsd [rcx], xmm0
    movsd [rcx + 8], xmm1
    inc dword [rbx + UgfxPath_point_count]
    ret

; rbx = path -> xmm0/xmm1 = current point
path_current:
    xorpd xmm0, xmm0
    xorpd xmm1, xmm1
    mov ecx, [rbx + UgfxPath_point_count]
    test ecx, ecx
    jz .current_done
    mov eax, [rbx + UgfxPath_verb_count]
    mov rdx, [rbx + UgfxPath_verbs]
    cmp byte [rdx + rax - 1], PATH_VERB_CLOSE
    jne .current_last
    mov ecx, [rbx + UgfxPath_start]
    inc ecx
.current_last:
    dec ecx
    shl rcx, 4
    add rcx, [rbx + UgfxPath_points]
    movsd xmm0, [rcx]
    movsd xmm1, [rcx + 8]
.current_done:
    ret

; rbx = path, xmm0/xmm1 = point -> eax = 0 or -ENOMEM. Starts a contour.
path_add_move:
    sub rsp, 24
    movsd [rsp], xmm0
    movsd [rsp + 8], xmm1
    ; a MOVE right after a MOVE replaces it
    mov eax, [rbx + UgfxPath_verb_count]
    test eax, eax
    jz .move_new
    mov rdx, [rbx + UgfxPath_verbs]
    cmp byte [rdx + rax - 1], PATH_VERB_MOVE
    jne .move_new
    mov ecx, [rbx + UgfxPath_point_count]
    dec ecx
    shl rcx, 4
    add rcx, [rbx + UgfxPath_points]
    movsd [rcx], xmm0
    movsd [rcx + 8], xmm1
    xor eax, eax
    add rsp, 24
    ret
.move_new:
    mov ecx, 1
    call path_reserve
    test eax, eax
    jnz .move_out
    mov eax, [rbx + UgfxPath_point_count]
    mov [rbx + UgfxPath_start], eax
    mov dword [rbx + UgfxPath_open], 1
    mov al, PATH_VERB_MOVE
    call path_push_verb
    movsd xmm0, [rsp]
    movsd xmm1, [rsp + 8]
    call path_push_point
    xor eax, eax
.move_out:
    add rsp, 24
    ret

; rbx = path -> eax = 0 or -ENOMEM. Opens a contour at the current point.
path_ensure_open:
    cmp dword [rbx + UgfxPath_open], 0
    jne .ensure_done
    call path_current
    jmp path_add_move
.ensure_done:
    xor eax, eax
    ret

; -----------------------------------------------------------------------------
; ugfx_path_move_to — rdi = UgfxPath*, xmm0 = x, xmm1 = y -> rax = 0, -errno
; -----------------------------------------------------------------------------
global ugfx_path_move_to
ugfx_path_move_to:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    call path_add_move
    movsxd rax, eax
    EPILOGUE_RESTORE rbx

; -----------------------------------------------------------------------------
; ugfx_path_line_to — rdi = UgfxPath*, xmm0 = x, xmm1 = y -> rax = 0, -errno
; -----------------------------------------------------------------------------
global ugfx_path_line_to
ugfx_path_line_to:
    PROLOGUE_SAVE rbx
    sub rsp, 16
    mov rbx, rdi
    movsd [rsp], xmm0
    movsd [rsp + 8], xmm1
    call path_ensure_open
    test eax, eax
    jnz .line_out
    mov ecx, 1
    call path_reserve
    test eax, eax
    jnz .line_out
    mov al, PATH_VERB_LINE
    call path_push_verb
    movsd xmm0, [rsp]
    movsd xmm1, [rsp + 8]
    call path_push_point
    xor eax, eax
.line_out:
    movsxd rax, eax
    add rsp, 16
    EPILOGUE_RESTORE rbx

; -----------------------------------------------------------------------------
; ugfx_path_quad_to — rdi = UgfxPath*, xmm0/xmm1 = control, xmm2/xmm3 = end
; -----------------------------------------------------------------------------
global ugfx_path_quad_to
ugfx_path_quad_to:
    PROLOGUE_SAVE rbx
    sub rsp, 32
    mov rbx, rdi
    movsd [rsp], xmm0
    movsd [rsp + 8], xmm1
    movsd [rsp + 16], xmm2
    movsd [rsp + 24], xmm3
    call path_ensure_open
    test eax, eax
    jnz .quad_out
    mov ecx, 2
    call path_reserve
    test eax, eax
    jnz .quad_out
    mov al, PATH_VERB_QUAD
    call path_push_verb
    movsd xmm0, [rsp]
    movsd xmm1, [rsp + 8]
    call path_push_point
    movsd xmm0, [rsp + 16]
    movsd xmm1, [rsp + 24]
    call path_push_point
    xor eax, eax
.quad_out:
    movsxd rax, eax
    add rsp, 32
    EPILOGUE_RESTORE rbx

; -----------------------------------------------------------------------------
; ugfx_path_cubic_to — rdi = UgfxPath*, xmm0/xmm1 = control 1,
;   xmm2/xmm3 = control 2, xmm4/xmm5 = end
; -----------------------------------------------------------------------------
global ugfx_path_cubic_to
ugfx_path_cubic_to:
    PROLOGUE_SAVE rbx
    sub rsp, 48
    mov rbx, rdi
    movsd [rsp], xmm0
    movsd [rsp + 8], xmm1
    movsd [rsp + 16], xmm2
    movsd [rsp + 24], xmm3
    movsd [rsp + 32], xmm4
    movsd [rsp + 40], xmm5
    call path_ensure_open
    test eax, eax
    jnz .cubic_out
    mov ecx, 3
    call path_reserve
    test eax, eax
    jnz .cubic_out
    mov al, PATH_VERB_CUBIC
    call path_push_verb
    movsd xmm0, [rsp]
    movsd xmm1, [rsp + 8]
    call path_push_point
    movsd xmm0, [rsp + 16]
    movsd xmm1, [rsp + 24]
    call path_push_point
    movsd xmm0, [rsp + 32]
    movsd xmm1, [rsp + 40]
    call path_push_point
    xor eax, eax
.cubic_out:
    movsxd rax, eax
    add rsp, 48
    EPILOGUE_RESTORE rbx

; -----------------------------------------------------------------------------
; ugfx_path_close — rdi = UgfxPath* -> rax = 0, -errno
; -----------------------------------------------------------------------------
global ugfx_path_close
ugfx_path_close:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    xor eax, eax
    cmp dword [rbx + UgfxPath_open], 0
    je .close_out
    xor ecx, ecx
    call path_reserve
    test eax, eax
    jnz .close_out
    mov al, PATH_VERB_CLOSE
    call path_push_verb
    mov dword [rbx + UgfxPath_open], 0
    xor eax, eax
.close_out:
    movsxd rax, eax
    EPILOGUE_RESTORE rbx

; -----------------------------------------------------------------------------
; (x, y) = ugfx_path_current(const UgfxPath*)
; -----------------------------------------------------------------------------
global ugfx_path_current
ugfx_path_current:
    push rbx
    mov rbx, rdi
    call path_current
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ugfx_path_transform — rdi = UgfxPath*, rsi = const double m[6]
; -----------------------------------------------------------------------------
global ugfx_path_transform
ugfx_path_transform:
    mov rax, rdi
    mov rdi, rsi
    mov rsi, [rax + UgfxPath_points]
    mov rdx, rsi
    mov ecx, [rax + UgfxPath_point_count]
    jmp umath_affine2_apply_array

; -----------------------------------------------------------------------------
; ugfx_path_bounds — rdi = UgfxPath*, rsi = double out[4] (x0, y0, x1, y1)
;   Bounds of all points, including curve controls (contains the curves).
;   -> rax = 0, or -EINVAL for an empty path (out untouched).
; -----------------------------------------------------------------------------
global ugfx_path_bounds
ugfx_path_bounds:
    mov ecx, [rdi + UgfxPath_point_count]
    test ecx, ecx
    jz .bounds_empty
    mov rdx, [rdi + UgfxPath_points]
    movsd xmm0, [rel path_huge]
    movapd xmm1, xmm0
    movsd xmm2, [rel path_neg_huge]
    movapd xmm3, xmm2
.bounds_point:
    movsd xmm4, [rdx]
    movsd xmm5, [rdx + 8]
    minsd xmm0, xmm4
    minsd xmm1, xmm5
    maxsd xmm2, xmm4
    maxsd xmm3, xmm5
    add rdx, 16
    dec ecx
    jnz .bounds_point
    movsd [rsi], xmm0
    movsd [rsi + 8], xmm1
    movsd [rsi + 16], xmm2
    movsd [rsi + 24], xmm3
    xor eax, eax
    ret
.bounds_empty:
    mov rax, -(EINVAL)
    ret

; -----------------------------------------------------------------------------
; ugfx_path_rasterize — rdi = UgfxPath*, rsi = UgfxRaster*,
;   rdx = const double m[6] or 0 for identity, xmm0 = tolerance in device
;   pixels (<= 0 or NaN: UGFX_PATH_TOLERANCE)
;   -> rax = 0, -EINVAL, -ENOMEM. Feeds edges only; fill with ugfx_raster_fill.
; -----------------------------------------------------------------------------
%define R_RASTER    0
%define R_MATRIX    8
%define R_TOL       16
%define R_VERB      24                  ; u32 verb index
%define R_POINT     28                  ; u32 point index
%define R_SEGS      32                  ; u64 segments of the current curve
%define R_SEG       40                  ; u64
%define R_CURVE     48                  ; f64[8] device-space control points
%define R_SIZE      112

global ugfx_path_rasterize
ugfx_path_rasterize:
    PROLOGUE_SAVE rbx, r12
    sub rsp, R_SIZE
    mov rbx, rdi
    test rdi, rdi
    jz .rz_bad
    test rsi, rsi
    jz .rz_bad
    cmp dword [rbx + UgfxPath_error], 0
    jne .rz_nomem
    mov [rsp + R_RASTER], rsi
    mov [rsp + R_MATRIX], rdx
    xorpd xmm1, xmm1
    ucomisd xmm0, xmm1
    jp .rz_default_tol
    ja .rz_tol_ready
.rz_default_tol:
    movsd xmm0, [rel path_default_tol]
.rz_tol_ready:
    movsd [rsp + R_TOL], xmm0
    mov dword [rsp + R_VERB], 0
    mov dword [rsp + R_POINT], 0
.rz_verb:
    mov eax, [rsp + R_VERB]
    cmp eax, [rbx + UgfxPath_verb_count]
    jae .rz_done
    inc dword [rsp + R_VERB]
    mov rdx, [rbx + UgfxPath_verbs]
    movzx eax, byte [rdx + rax]
    cmp eax, PATH_VERB_MOVE
    je .rz_move
    cmp eax, PATH_VERB_LINE
    je .rz_line
    cmp eax, PATH_VERB_QUAD
    je .rz_quad
    cmp eax, PATH_VERB_CUBIC
    je .rz_cubic
    cmp eax, PATH_VERB_CLOSE
    je .rz_close
    jmp .rz_bad
.rz_move:
    call .rz_load_point
    call .rz_fix
    mov rdi, [rsp + R_RASTER]
    call ugfx_raster_move_to
    jmp .rz_verb
.rz_line:
    call .rz_load_point
    call .rz_fix
    mov rdi, [rsp + R_RASTER]
    call ugfx_raster_line_to
    jmp .rz_verb
.rz_close:
    mov rdi, [rsp + R_RASTER]
    call ugfx_raster_close
    jmp .rz_verb
.rz_quad:
    mov r12d, 2
    jmp .rz_curve
.rz_cubic:
    mov r12d, 3
.rz_curve:
    ; curve[0] = previous point (device), then r12 control/end points
    mov eax, [rsp + R_POINT]
    test eax, eax
    jz .rz_bad                          ; a curve always follows a point
    dec eax
    call .rz_device_at
    movsd [rsp + R_CURVE], xmm0
    movsd [rsp + R_CURVE + 8], xmm1
    xor ecx, ecx
.rz_curve_points:
    push rcx
    mov eax, [rsp + 8 + R_POINT]
    add eax, ecx
    call .rz_device_at_frame8
    pop rcx
    lea rdx, [rcx + 1]
    shl rdx, 4
    movsd [rsp + R_CURVE + rdx], xmm0
    movsd [rsp + R_CURVE + rdx + 8], xmm1
    inc ecx
    cmp ecx, r12d
    jb .rz_curve_points
    add [rsp + R_POINT], r12d
    lea rdi, [rsp + R_CURVE]
    movsd xmm0, [rsp + R_TOL]
    cmp r12d, 2
    jne .rz_cubic_segments
    call umath_bezier_quad_segments
    jmp .rz_have_segments
.rz_cubic_segments:
    call umath_bezier_cubic_segments
.rz_have_segments:
    mov [rsp + R_SEGS], rax
    mov qword [rsp + R_SEG], 1
.rz_segment:
    mov rax, [rsp + R_SEG]
    cmp rax, [rsp + R_SEGS]
    jae .rz_curve_end
    cvtsi2sd xmm0, rax
    cvtsi2sd xmm1, qword [rsp + R_SEGS]
    divsd xmm0, xmm1                    ; t
    lea rdi, [rsp + R_CURVE]
    cmp r12d, 2
    jne .rz_cubic_eval
    call umath_bezier_quad_eval
    jmp .rz_have_point
.rz_cubic_eval:
    call umath_bezier_cubic_eval
.rz_have_point:
    call .rz_fix
    mov rdi, [rsp + R_RASTER]
    call ugfx_raster_line_to
    inc qword [rsp + R_SEG]
    jmp .rz_segment
.rz_curve_end:
    mov eax, r12d
    shl eax, 4
    movsd xmm0, [rsp + R_CURVE + rax]   ; exact end point
    movsd xmm1, [rsp + R_CURVE + rax + 8]
    call .rz_fix
    mov rdi, [rsp + R_RASTER]
    call ugfx_raster_line_to
    jmp .rz_verb
.rz_done:
    xor eax, eax
    add rsp, R_SIZE
    EPILOGUE_RESTORE rbx, r12
.rz_bad:
    mov rax, -(EINVAL)
    add rsp, R_SIZE
    EPILOGUE_RESTORE rbx, r12
.rz_nomem:
    mov rax, -(ENOMEM)
    add rsp, R_SIZE
    EPILOGUE_RESTORE rbx, r12

; next point -> device xmm0/xmm1 (called from the frame, +8 return address)
.rz_load_point:
    mov eax, [rsp + 8 + R_POINT]
    inc dword [rsp + 8 + R_POINT]
    mov rdx, [rsp + 8 + R_MATRIX]
    jmp .rz_device_common
; eax = point index -> device xmm0/xmm1 (from the frame, +8)
.rz_device_at:
    mov rdx, [rsp + 8 + R_MATRIX]
    jmp .rz_device_common
; same, with one extra qword pushed on the frame (+16)
.rz_device_at_frame8:
    mov rdx, [rsp + 16 + R_MATRIX]
.rz_device_common:
    shl rax, 4
    add rax, [rbx + UgfxPath_points]
    movsd xmm0, [rax]
    movsd xmm1, [rax + 8]
    test rdx, rdx
    jz .rz_device_done
    mov rdi, rdx
    jmp umath_affine2_apply             ; returns to our caller
.rz_device_done:
    ret

; xmm0/xmm1 (device f64) -> esi/edx = 24.8 fixed, rounded, clamped
.rz_fix:
    mulsd xmm0, [rel path_fix_scale]
    mulsd xmm1, [rel path_fix_scale]
    minsd xmm0, [rel path_fix_max]
    maxsd xmm0, [rel path_fix_min]
    minsd xmm1, [rel path_fix_max]
    maxsd xmm1, [rel path_fix_min]
    cvtsd2si esi, xmm0
    cvtsd2si edx, xmm1
    ret

section .data
global ugfx_path_version
ugfx_path_version: dq 0x020000
