; =============================================================================
; Utkarsha OS — lib/ugfx/2d/shapes.asm
; =============================================================================
; Shape builders that append closed contours (or, for add_arc, extend the
; current one) to a UgfxPath. Angles are radians, positive turning +x
; towards +y (clockwise on a y-down screen); every shape is wound that way.
; Curves come from lib/umath/geom/arc (cubics within 0.03% of the ellipse).
;
;   ugfx_path_add_rect           x, y, w, h
;   ugfx_path_add_rounded_rect   x, y, w, h, r
;   ugfx_path_add_rounded_rect_radii  x, y, w, h, radii[4] (tl, tr, br, bl)
;   ugfx_path_add_ellipse        cx, cy, rx, ry
;   ugfx_path_add_circle         cx, cy, r
;   ugfx_path_add_arc            cx, cy, rx, ry, start, sweep (open)
;   ugfx_path_add_pie            cx, cy, rx, ry, start, sweep
;   ugfx_path_add_ring_sector    cx, cy, r_outer, r_inner, start, sweep
;   ugfx_path_add_polygon        points[n], n
;   ugfx_path_add_star           cx, cy, r_outer, r_inner, tips, rotation
; All return rax = 0 or a negative errno (-EINVAL for bad sizes or counts).
; =============================================================================

%include "ugfx.inc"

extern ugfx_path_move_to
extern ugfx_path_line_to
extern ugfx_path_cubic_to
extern ugfx_path_close
extern umath_arc_point
extern umath_arc_to_cubics

section .rodata
align 8
shape_half:         dq 0.5
shape_zero:         dq 0.0
shape_pi:           dq 3.141592653589793
shape_half_pi:      dq 1.5707963267948966
shape_neg_half_pi:  dq -1.5707963267948966
shape_two_pi:       dq 6.283185307179586

section .text

; -----------------------------------------------------------------------------
; shape_arc — rbx = path; xmm0..xmm5 = cx, cy, rx, ry, start, sweep.
;   Lines (or moves, with no open contour) to the arc start, then appends
;   its cubics. -> eax = 0 or -errno.
; -----------------------------------------------------------------------------
%define SA_ARGS     0                   ; f64[6]
%define SA_OUT      48                  ; f64[24]
%define SA_COUNT    240
%define SA_INDEX    248
%define SA_MOVE     256                 ; u32: start with a move
%define SA_SIZE     264

shape_arc:
    sub rsp, SA_SIZE
    movsd [rsp + SA_ARGS], xmm0
    movsd [rsp + SA_ARGS + 8], xmm1
    movsd [rsp + SA_ARGS + 16], xmm2
    movsd [rsp + SA_ARGS + 24], xmm3
    movsd [rsp + SA_ARGS + 32], xmm4
    movsd [rsp + SA_ARGS + 40], xmm5
    mov eax, [rbx + UgfxPath_open]
    xor eax, 1
    mov [rsp + SA_MOVE], eax
    movsd xmm4, [rsp + SA_ARGS + 32]    ; start angle
    call umath_arc_point
    mov rdi, rbx
    cmp dword [rsp + SA_MOVE], 0
    je .arc_line
    call ugfx_path_move_to
    jmp .arc_started
.arc_line:
    call ugfx_path_line_to
.arc_started:
    test eax, eax
    jnz .arc_out
    lea rdi, [rsp + SA_OUT]
    movsd xmm0, [rsp + SA_ARGS]
    movsd xmm1, [rsp + SA_ARGS + 8]
    movsd xmm2, [rsp + SA_ARGS + 16]
    movsd xmm3, [rsp + SA_ARGS + 24]
    movsd xmm4, [rsp + SA_ARGS + 32]
    movsd xmm5, [rsp + SA_ARGS + 40]
    call umath_arc_to_cubics
    mov [rsp + SA_COUNT], rax
    mov qword [rsp + SA_INDEX], 0
.arc_piece:
    mov rax, [rsp + SA_INDEX]
    cmp rax, [rsp + SA_COUNT]
    jae .arc_done
    imul rax, rax, 48
    lea rax, [rsp + SA_OUT + rax]
    movsd xmm0, [rax]
    movsd xmm1, [rax + 8]
    movsd xmm2, [rax + 16]
    movsd xmm3, [rax + 24]
    movsd xmm4, [rax + 32]
    movsd xmm5, [rax + 40]
    mov rdi, rbx
    call ugfx_path_cubic_to
    test eax, eax
    jnz .arc_out
    inc qword [rsp + SA_INDEX]
    jmp .arc_piece
.arc_done:
    xor eax, eax
.arc_out:
    add rsp, SA_SIZE
    ret

; xmm0 = value -> CF/ZF: "value > 0" is ja after the macro; NaN is not > 0
%macro SHAPE_REQUIRE_POSITIVE 2
    xorpd xmm15, xmm15
    ucomisd %1, xmm15
    jp %2
    jbe %2
%endmacro

; -----------------------------------------------------------------------------
; ugfx_path_add_rect — rdi = path, xmm0..xmm3 = x, y, w, h
; -----------------------------------------------------------------------------
global ugfx_path_add_rect
ugfx_path_add_rect:
    PROLOGUE_SAVE rbx
    sub rsp, 32
    mov rbx, rdi
    SHAPE_REQUIRE_POSITIVE xmm2, .rect_bad
    SHAPE_REQUIRE_POSITIVE xmm3, .rect_bad
    movsd [rsp], xmm0
    movsd [rsp + 8], xmm1
    addsd xmm2, xmm0
    addsd xmm3, xmm1
    movsd [rsp + 16], xmm2              ; x1
    movsd [rsp + 24], xmm3              ; y1
    mov rdi, rbx
    call ugfx_path_move_to
    test eax, eax
    jnz .rect_out
    movsd xmm0, [rsp + 16]
    movsd xmm1, [rsp + 8]
    mov rdi, rbx
    call ugfx_path_line_to
    test eax, eax
    jnz .rect_out
    movsd xmm0, [rsp + 16]
    movsd xmm1, [rsp + 24]
    mov rdi, rbx
    call ugfx_path_line_to
    test eax, eax
    jnz .rect_out
    movsd xmm0, [rsp]
    movsd xmm1, [rsp + 24]
    mov rdi, rbx
    call ugfx_path_line_to
    test eax, eax
    jnz .rect_out
    mov rdi, rbx
    call ugfx_path_close
.rect_out:
    add rsp, 32
    EPILOGUE_RESTORE rbx
.rect_bad:
    mov rax, -(EINVAL)
    add rsp, 32
    EPILOGUE_RESTORE rbx

; -----------------------------------------------------------------------------
; ugfx_path_add_rounded_rect — rdi = path, xmm0..xmm3 = x, y, w, h, xmm4 = r
; -----------------------------------------------------------------------------
global ugfx_path_add_rounded_rect
ugfx_path_add_rounded_rect:
    sub rsp, 40
    movsd [rsp], xmm4
    movsd [rsp + 8], xmm4
    movsd [rsp + 16], xmm4
    movsd [rsp + 24], xmm4
    mov rsi, rsp
    call ugfx_path_add_rounded_rect_radii
    add rsp, 40
    ret

; -----------------------------------------------------------------------------
; ugfx_path_add_rounded_rect_radii — rdi = path, xmm0..xmm3 = x, y, w, h,
;   rsi = const double radii[4] (top-left, top-right, bottom-right,
;   bottom-left). Radii below zero count as zero; when two radii on one
;   side exceed it, all radii are scaled down together so they fit.
; -----------------------------------------------------------------------------
%define RR_X    0
%define RR_Y    8
%define RR_W    16
%define RR_H    24
%define RR_R    32                      ; f64[4] clamped radii
%define RR_SIZE 64

global ugfx_path_add_rounded_rect_radii
ugfx_path_add_rounded_rect_radii:
    PROLOGUE_SAVE rbx
    sub rsp, RR_SIZE
    mov rbx, rdi
    SHAPE_REQUIRE_POSITIVE xmm2, .rr_bad
    SHAPE_REQUIRE_POSITIVE xmm3, .rr_bad
    movsd [rsp + RR_X], xmm0
    movsd [rsp + RR_Y], xmm1
    movsd [rsp + RR_W], xmm2
    movsd [rsp + RR_H], xmm3
    ; clamp each radius to >= 0 (NaN -> 0)
    xor ecx, ecx
.rr_clamp:
    movsd xmm0, [rsi + rcx * 8]
    maxsd xmm0, [rel shape_zero]        ; NaN -> 0
    movsd [rsp + RR_R + rcx * 8], xmm0
    inc ecx
    cmp ecx, 4
    jb .rr_clamp
    ; scale = min(1, w / (tl + tr), w / (bl + br), h / (tl + bl), h / (tr + br))
    movsd xmm7, [rel shape_half]
    addsd xmm7, xmm7                    ; 1.0
    movsd xmm0, [rsp + RR_R]
    addsd xmm0, [rsp + RR_R + 8]
    movsd xmm6, [rsp + RR_W]
    call .rr_limit
    movsd xmm0, [rsp + RR_R + 24]
    addsd xmm0, [rsp + RR_R + 16]
    movsd xmm6, [rsp + RR_W]
    call .rr_limit
    movsd xmm0, [rsp + RR_R]
    addsd xmm0, [rsp + RR_R + 24]
    movsd xmm6, [rsp + RR_H]
    call .rr_limit
    movsd xmm0, [rsp + RR_R + 8]
    addsd xmm0, [rsp + RR_R + 16]
    movsd xmm6, [rsp + RR_H]
    call .rr_limit
    xor ecx, ecx
.rr_scale:
    movsd xmm0, [rsp + RR_R + rcx * 8]
    mulsd xmm0, xmm7
    movsd [rsp + RR_R + rcx * 8], xmm0
    inc ecx
    cmp ecx, 4
    jb .rr_scale
    ; top edge from after the top-left corner
    movsd xmm0, [rsp + RR_X]
    addsd xmm0, [rsp + RR_R]
    movsd xmm1, [rsp + RR_Y]
    mov rdi, rbx
    call ugfx_path_move_to
    test eax, eax
    jnz .rr_out
    ; top-right corner: centre (x + w - r, y + r), from -pi/2, a quarter turn
    movsd xmm0, [rsp + RR_X]
    addsd xmm0, [rsp + RR_W]
    subsd xmm0, [rsp + RR_R + 8]
    movsd xmm1, [rsp + RR_Y]
    addsd xmm1, [rsp + RR_R + 8]
    movsd xmm2, [rsp + RR_R + 8]
    movsd xmm4, [rel shape_neg_half_pi]
    call .rr_corner
    test eax, eax
    jnz .rr_out
    ; bottom-right: centre (x + w - r, y + h - r), from 0
    movsd xmm0, [rsp + RR_X]
    addsd xmm0, [rsp + RR_W]
    subsd xmm0, [rsp + RR_R + 16]
    movsd xmm1, [rsp + RR_Y]
    addsd xmm1, [rsp + RR_H]
    subsd xmm1, [rsp + RR_R + 16]
    movsd xmm2, [rsp + RR_R + 16]
    movsd xmm4, [rel shape_zero]
    call .rr_corner
    test eax, eax
    jnz .rr_out
    ; bottom-left: centre (x + r, y + h - r), from pi/2
    movsd xmm0, [rsp + RR_X]
    addsd xmm0, [rsp + RR_R + 24]
    movsd xmm1, [rsp + RR_Y]
    addsd xmm1, [rsp + RR_H]
    subsd xmm1, [rsp + RR_R + 24]
    movsd xmm2, [rsp + RR_R + 24]
    movsd xmm4, [rel shape_half_pi]
    call .rr_corner
    test eax, eax
    jnz .rr_out
    ; top-left: centre (x + r, y + r), from pi
    movsd xmm0, [rsp + RR_X]
    addsd xmm0, [rsp + RR_R]
    movsd xmm1, [rsp + RR_Y]
    addsd xmm1, [rsp + RR_R]
    movsd xmm2, [rsp + RR_R]
    movsd xmm4, [rel shape_pi]
    call .rr_corner
    test eax, eax
    jnz .rr_out
    mov rdi, rbx
    call ugfx_path_close
.rr_out:
    add rsp, RR_SIZE
    EPILOGUE_RESTORE rbx
.rr_bad:
    mov rax, -(EINVAL)
    add rsp, RR_SIZE
    EPILOGUE_RESTORE rbx

; xmm0 = radius pair sum, xmm6 = side; xmm7 = min(xmm7, side / sum)
.rr_limit:
    movsd xmm1, [rel shape_zero]
    ucomisd xmm0, xmm1
    jbe .rr_limit_done
    divsd xmm6, xmm0
    minsd xmm7, xmm6
.rr_limit_done:
    ret

; xmm0/xmm1 = centre, xmm2 = radius, xmm4 = start angle. A zero radius is
; a sharp corner: just a line to the centre (the corner point itself).
.rr_corner:
    movsd xmm3, [rel shape_zero]
    ucomisd xmm2, xmm3
    ja .rr_round
    mov rdi, rbx
    jmp ugfx_path_line_to
.rr_round:
    movapd xmm3, xmm2
    movsd xmm5, [rel shape_half_pi]
    jmp shape_arc

; -----------------------------------------------------------------------------
; ugfx_path_add_ellipse — rdi = path, xmm0..xmm3 = cx, cy, rx, ry
; -----------------------------------------------------------------------------
global ugfx_path_add_ellipse
ugfx_path_add_ellipse:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    SHAPE_REQUIRE_POSITIVE xmm2, .ellipse_bad
    SHAPE_REQUIRE_POSITIVE xmm3, .ellipse_bad
    cmp dword [rbx + UgfxPath_open], 0
    je .ellipse_closed
    sub rsp, 32
    movsd [rsp], xmm0
    movsd [rsp + 8], xmm1
    movsd [rsp + 16], xmm2
    movsd [rsp + 24], xmm3
    mov rdi, rbx
    call ugfx_path_close                ; the ellipse is its own contour
    movsd xmm0, [rsp]
    movsd xmm1, [rsp + 8]
    movsd xmm2, [rsp + 16]
    movsd xmm3, [rsp + 24]
    add rsp, 32
.ellipse_closed:
    movsd xmm4, [rel shape_zero]
    movsd xmm5, [rel shape_two_pi]
    call shape_arc
    test eax, eax
    jnz .ellipse_out
    mov rdi, rbx
    call ugfx_path_close
.ellipse_out:
    EPILOGUE_RESTORE rbx
.ellipse_bad:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx

; -----------------------------------------------------------------------------
; ugfx_path_add_circle — rdi = path, xmm0..xmm2 = cx, cy, r
; -----------------------------------------------------------------------------
global ugfx_path_add_circle
ugfx_path_add_circle:
    movapd xmm3, xmm2
    jmp ugfx_path_add_ellipse

; -----------------------------------------------------------------------------
; ugfx_path_add_arc — rdi = path, xmm0..xmm5 = cx, cy, rx, ry, start, sweep.
;   Continues the open contour with a line to the arc start (or starts one).
; -----------------------------------------------------------------------------
global ugfx_path_add_arc
ugfx_path_add_arc:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    SHAPE_REQUIRE_POSITIVE xmm2, .arc_bad
    SHAPE_REQUIRE_POSITIVE xmm3, .arc_bad
    call shape_arc
    movsxd rax, eax
    EPILOGUE_RESTORE rbx
.arc_bad:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx

; -----------------------------------------------------------------------------
; ugfx_path_add_pie — rdi = path, xmm0..xmm5 = cx, cy, rx, ry, start, sweep
; -----------------------------------------------------------------------------
global ugfx_path_add_pie
ugfx_path_add_pie:
    PROLOGUE_SAVE rbx
    sub rsp, 48
    mov rbx, rdi
    SHAPE_REQUIRE_POSITIVE xmm2, .pie_bad
    SHAPE_REQUIRE_POSITIVE xmm3, .pie_bad
    movsd [rsp], xmm0
    movsd [rsp + 8], xmm1
    movsd [rsp + 16], xmm2
    movsd [rsp + 24], xmm3
    movsd [rsp + 32], xmm4
    movsd [rsp + 40], xmm5
    mov rdi, rbx
    call ugfx_path_close
    movsd xmm0, [rsp]
    movsd xmm1, [rsp + 8]
    mov rdi, rbx
    call ugfx_path_move_to              ; the centre
    test eax, eax
    jnz .pie_out
    movsd xmm0, [rsp]
    movsd xmm1, [rsp + 8]
    movsd xmm2, [rsp + 16]
    movsd xmm3, [rsp + 24]
    movsd xmm4, [rsp + 32]
    movsd xmm5, [rsp + 40]
    call shape_arc
    test eax, eax
    jnz .pie_out
    mov rdi, rbx
    call ugfx_path_close
.pie_out:
    movsxd rax, eax
    add rsp, 48
    EPILOGUE_RESTORE rbx
.pie_bad:
    mov rax, -(EINVAL)
    add rsp, 48
    EPILOGUE_RESTORE rbx

; -----------------------------------------------------------------------------
; ugfx_path_add_ring_sector — rdi = path, xmm0..xmm5 = cx, cy, r_outer,
;   r_inner, start, sweep. The band between the two radii over the sweep;
;   r_inner of 0 gives a pie.
; -----------------------------------------------------------------------------
global ugfx_path_add_ring_sector
ugfx_path_add_ring_sector:
    PROLOGUE_SAVE rbx
    sub rsp, 48
    mov rbx, rdi
    SHAPE_REQUIRE_POSITIVE xmm2, .ring_bad
    movsd [rsp], xmm0
    movsd [rsp + 8], xmm1
    movsd [rsp + 16], xmm2
    movsd [rsp + 24], xmm3
    movsd [rsp + 32], xmm4
    movsd [rsp + 40], xmm5
    xorpd xmm6, xmm6
    ucomisd xmm3, xmm6
    jp .ring_bad
    jb .ring_bad
    ucomisd xmm3, xmm2
    jae .ring_bad                       ; inner must be inside outer
    mov rdi, rbx
    call ugfx_path_close
    ; outer arc forwards
    movsd xmm0, [rsp]
    movsd xmm1, [rsp + 8]
    movsd xmm2, [rsp + 16]
    movsd xmm3, [rsp + 16]
    movsd xmm4, [rsp + 32]
    movsd xmm5, [rsp + 40]
    call shape_arc
    test eax, eax
    jnz .ring_out
    ; inner arc backwards (or the centre for a pie)
    movsd xmm2, [rsp + 24]
    xorpd xmm6, xmm6
    ucomisd xmm2, xmm6
    ja .ring_inner
    movsd xmm0, [rsp]
    movsd xmm1, [rsp + 8]
    mov rdi, rbx
    call ugfx_path_line_to
    test eax, eax
    jnz .ring_out
    jmp .ring_close
.ring_inner:
    movsd xmm0, [rsp]
    movsd xmm1, [rsp + 8]
    movapd xmm3, xmm2
    movsd xmm4, [rsp + 32]
    addsd xmm4, [rsp + 40]              ; end angle
    xorpd xmm5, xmm5
    subsd xmm5, [rsp + 40]              ; -sweep
    call shape_arc
    test eax, eax
    jnz .ring_out
.ring_close:
    mov rdi, rbx
    call ugfx_path_close
.ring_out:
    movsxd rax, eax
    add rsp, 48
    EPILOGUE_RESTORE rbx
.ring_bad:
    mov rax, -(EINVAL)
    add rsp, 48
    EPILOGUE_RESTORE rbx

; -----------------------------------------------------------------------------
; ugfx_path_add_polygon — rdi = path, rsi = const double points[2n], edx = n
;   (n >= 2); a closed contour through the points.
; -----------------------------------------------------------------------------
global ugfx_path_add_polygon
ugfx_path_add_polygon:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    test rsi, rsi
    jz .poly_bad
    cmp edx, 2
    jl .poly_bad
    mov rdi, rbx
    call ugfx_path_close
    movsd xmm0, [r12]
    movsd xmm1, [r12 + 8]
    mov rdi, rbx
    call ugfx_path_move_to
    test eax, eax
    jnz .poly_out
.poly_point:
    add r12, 16
    dec r13d
    jz .poly_close
    movsd xmm0, [r12]
    movsd xmm1, [r12 + 8]
    mov rdi, rbx
    call ugfx_path_line_to
    test eax, eax
    jnz .poly_out
    jmp .poly_point
.poly_close:
    mov rdi, rbx
    call ugfx_path_close
.poly_out:
    movsxd rax, eax
    EPILOGUE_RESTORE rbx, r12, r13
.poly_bad:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12, r13

; -----------------------------------------------------------------------------
; ugfx_path_add_star — rdi = path, xmm0..xmm3 = cx, cy, r_outer, r_inner,
;   esi = tips (>= 2), xmm4 = rotation of the first tip.
;   Alternates 2 * tips vertices between the two radii.
; -----------------------------------------------------------------------------
%define ST_ARGS     0                   ; cx, cy, ro, ri, rotation
%define ST_STEP     40
%define ST_I        48
%define ST_N        52
%define ST_SIZE     64

global ugfx_path_add_star
ugfx_path_add_star:
    PROLOGUE_SAVE rbx
    sub rsp, ST_SIZE
    mov rbx, rdi
    cmp esi, 2
    jl .star_bad
    cmp esi, 4096
    jg .star_bad
    SHAPE_REQUIRE_POSITIVE xmm2, .star_bad
    SHAPE_REQUIRE_POSITIVE xmm3, .star_bad
    movsd [rsp + ST_ARGS], xmm0
    movsd [rsp + ST_ARGS + 8], xmm1
    movsd [rsp + ST_ARGS + 16], xmm2
    movsd [rsp + ST_ARGS + 24], xmm3
    movsd [rsp + ST_ARGS + 32], xmm4
    lea eax, [rsi + rsi]
    mov [rsp + ST_N], eax
    cvtsi2sd xmm0, eax
    movsd xmm1, [rel shape_two_pi]
    divsd xmm1, xmm0
    movsd [rsp + ST_STEP], xmm1
    mov dword [rsp + ST_I], 0
    mov rdi, rbx
    call ugfx_path_close
.star_vertex:
    mov eax, [rsp + ST_I]
    cmp eax, [rsp + ST_N]
    jae .star_close
    cvtsi2sd xmm4, eax
    mulsd xmm4, [rsp + ST_STEP]
    addsd xmm4, [rsp + ST_ARGS + 32]
    movsd xmm2, [rsp + ST_ARGS + 16]    ; outer radius on even vertices
    test eax, 1
    jz .star_radius
    movsd xmm2, [rsp + ST_ARGS + 24]
.star_radius:
    movapd xmm3, xmm2
    movsd xmm0, [rsp + ST_ARGS]
    movsd xmm1, [rsp + ST_ARGS + 8]
    call umath_arc_point
    mov rdi, rbx
    cmp dword [rsp + ST_I], 0
    jne .star_line
    call ugfx_path_move_to
    jmp .star_next
.star_line:
    call ugfx_path_line_to
.star_next:
    test eax, eax
    jnz .star_out
    inc dword [rsp + ST_I]
    jmp .star_vertex
.star_close:
    mov rdi, rbx
    call ugfx_path_close
.star_out:
    movsxd rax, eax
    add rsp, ST_SIZE
    EPILOGUE_RESTORE rbx
.star_bad:
    mov rax, -(EINVAL)
    add rsp, ST_SIZE
    EPILOGUE_RESTORE rbx

section .data
global ugfx_shapes_version
ugfx_shapes_version: dq 0x010000
