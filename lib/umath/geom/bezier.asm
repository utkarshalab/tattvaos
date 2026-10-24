%ifndef GUARD_LIB_UMATH_GEOM_BEZIER_ASM
%define GUARD_LIB_UMATH_GEOM_BEZIER_ASM
; =============================================================================
; umath - unified math library
; geom/bezier.asm - quadratic and cubic Bezier curves (f64)
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; A quadratic is 3 control points (6 doubles: x0 y0 x1 y1 x2 y2), a cubic
; 4 points (8 doubles). Points come back as (x, y) in xmm0/xmm1.
;
;   eval      B(t) by de Casteljau (stable for t in [0, 1])
;   tangent   B'(t), the derivative vector
;   split     de Casteljau at t: left and right halves sharing the middle
;             point, written as one point array (quad 5 points, cubic 7)
;   segments  how many equal-t line segments keep the polyline within tol
;             of the curve (Wang's formula):
;                 quad  n = ceil(sqrt(L / (4 tol))),      L = |p0 - 2p1 + p2|
;                 cubic n = ceil(sqrt(3 L / (4 tol))),    L = max |second differences|
;             The result is at least 1 and at most UMATH_BEZIER_MAX_SEGMENTS;
;             a non-positive or non-finite tol, or non-finite points, give 1.
; =============================================================================

bits 64

%define UMATH_BEZIER_MAX_SEGMENTS 4096

section .rodata
align 8
bezier_one:         dq 1.0
bezier_two:         dq 2.0
bezier_three:       dq 3.0
bezier_quarter:     dq 0.25
bezier_three_qtr:   dq 0.75
bezier_max_seg:     dq 4096.0

section .text

; de Casteljau step: %1 = lerp(%1, %2, t) for one coordinate, t in xmm15.
; %3 is a scratch register.
%macro BZ_LERP 3
    movapd %3, %2
    subsd %3, %1
    mulsd %3, xmm15
    addsd %1, %3
%endmacro

; -----------------------------------------------------------------------------
; (x, y) = umath_bezier_quad_eval(const double p[6], double t)
; -----------------------------------------------------------------------------
global umath_bezier_quad_eval
umath_bezier_quad_eval:
    movapd xmm15, xmm0
    movsd xmm0, [rdi]
    movsd xmm1, [rdi + 8]
    movsd xmm2, [rdi + 16]
    movsd xmm3, [rdi + 24]
    movsd xmm4, [rdi + 32]
    movsd xmm5, [rdi + 40]
    BZ_LERP xmm0, xmm2, xmm6            ; q0 = lerp(p0, p1)
    BZ_LERP xmm1, xmm3, xmm6
    BZ_LERP xmm2, xmm4, xmm6            ; q1 = lerp(p1, p2)
    BZ_LERP xmm3, xmm5, xmm6
    BZ_LERP xmm0, xmm2, xmm6            ; B = lerp(q0, q1)
    BZ_LERP xmm1, xmm3, xmm6
    ret

; -----------------------------------------------------------------------------
; (x, y) = umath_bezier_cubic_eval(const double p[8], double t)
; -----------------------------------------------------------------------------
global umath_bezier_cubic_eval
umath_bezier_cubic_eval:
    movapd xmm15, xmm0
    movsd xmm0, [rdi]
    movsd xmm1, [rdi + 8]
    movsd xmm2, [rdi + 16]
    movsd xmm3, [rdi + 24]
    movsd xmm4, [rdi + 32]
    movsd xmm5, [rdi + 40]
    movsd xmm6, [rdi + 48]
    movsd xmm7, [rdi + 56]
    BZ_LERP xmm0, xmm2, xmm8
    BZ_LERP xmm1, xmm3, xmm8
    BZ_LERP xmm2, xmm4, xmm8
    BZ_LERP xmm3, xmm5, xmm8
    BZ_LERP xmm4, xmm6, xmm8
    BZ_LERP xmm5, xmm7, xmm8
    BZ_LERP xmm0, xmm2, xmm8
    BZ_LERP xmm1, xmm3, xmm8
    BZ_LERP xmm2, xmm4, xmm8
    BZ_LERP xmm3, xmm5, xmm8
    BZ_LERP xmm0, xmm2, xmm8
    BZ_LERP xmm1, xmm3, xmm8
    ret

; -----------------------------------------------------------------------------
; (dx, dy) = umath_bezier_quad_tangent(const double p[6], double t)
;   B'(t) = 2 * lerp(p1 - p0, p2 - p1, t)
; -----------------------------------------------------------------------------
global umath_bezier_quad_tangent
umath_bezier_quad_tangent:
    movapd xmm15, xmm0
    movsd xmm0, [rdi + 16]
    subsd xmm0, [rdi]
    movsd xmm1, [rdi + 24]
    subsd xmm1, [rdi + 8]
    movsd xmm2, [rdi + 32]
    subsd xmm2, [rdi + 16]
    movsd xmm3, [rdi + 40]
    subsd xmm3, [rdi + 24]
    BZ_LERP xmm0, xmm2, xmm6
    BZ_LERP xmm1, xmm3, xmm6
    mulsd xmm0, [rel bezier_two]
    mulsd xmm1, [rel bezier_two]
    ret

; -----------------------------------------------------------------------------
; (dx, dy) = umath_bezier_cubic_tangent(const double p[8], double t)
;   B'(t) = 3 * quad_eval(p1 - p0, p2 - p1, p3 - p2; t)
; -----------------------------------------------------------------------------
global umath_bezier_cubic_tangent
umath_bezier_cubic_tangent:
    movapd xmm15, xmm0
    movsd xmm0, [rdi + 16]
    subsd xmm0, [rdi]
    movsd xmm1, [rdi + 24]
    subsd xmm1, [rdi + 8]
    movsd xmm2, [rdi + 32]
    subsd xmm2, [rdi + 16]
    movsd xmm3, [rdi + 40]
    subsd xmm3, [rdi + 24]
    movsd xmm4, [rdi + 48]
    subsd xmm4, [rdi + 32]
    movsd xmm5, [rdi + 56]
    subsd xmm5, [rdi + 40]
    BZ_LERP xmm0, xmm2, xmm6
    BZ_LERP xmm1, xmm3, xmm6
    BZ_LERP xmm2, xmm4, xmm6
    BZ_LERP xmm3, xmm5, xmm6
    BZ_LERP xmm0, xmm2, xmm6
    BZ_LERP xmm1, xmm3, xmm6
    mulsd xmm0, [rel bezier_three]
    mulsd xmm1, [rel bezier_three]
    ret

; -----------------------------------------------------------------------------
; umath_bezier_quad_split(const double p[6], double t, double out[10])
;   out = left (p0, q0, B) + right (B, q1, p2): five points.
;   out must not alias p.
; -----------------------------------------------------------------------------
global umath_bezier_quad_split
umath_bezier_quad_split:
    movapd xmm15, xmm0
    movsd xmm0, [rdi]
    movsd xmm1, [rdi + 8]
    movsd xmm2, [rdi + 16]
    movsd xmm3, [rdi + 24]
    movsd xmm4, [rdi + 32]
    movsd xmm5, [rdi + 40]
    movsd [rsi], xmm0
    movsd [rsi + 8], xmm1
    movsd [rsi + 64], xmm4
    movsd [rsi + 72], xmm5
    BZ_LERP xmm0, xmm2, xmm6            ; q0
    BZ_LERP xmm1, xmm3, xmm6
    BZ_LERP xmm2, xmm4, xmm6            ; q1
    BZ_LERP xmm3, xmm5, xmm6
    movsd [rsi + 16], xmm0
    movsd [rsi + 24], xmm1
    movsd [rsi + 48], xmm2
    movsd [rsi + 56], xmm3
    BZ_LERP xmm0, xmm2, xmm6            ; B
    BZ_LERP xmm1, xmm3, xmm6
    movsd [rsi + 32], xmm0
    movsd [rsi + 40], xmm1
    ret

; -----------------------------------------------------------------------------
; umath_bezier_cubic_split(const double p[8], double t, double out[14])
;   out = left (p0, a, d, B) + right (B, e, c, p3): seven points.
;   out must not alias p.
; -----------------------------------------------------------------------------
global umath_bezier_cubic_split
umath_bezier_cubic_split:
    movapd xmm15, xmm0
    movsd xmm0, [rdi]
    movsd xmm1, [rdi + 8]
    movsd xmm2, [rdi + 16]
    movsd xmm3, [rdi + 24]
    movsd xmm4, [rdi + 32]
    movsd xmm5, [rdi + 40]
    movsd xmm6, [rdi + 48]
    movsd xmm7, [rdi + 56]
    movsd [rsi], xmm0
    movsd [rsi + 8], xmm1
    movsd [rsi + 96], xmm6
    movsd [rsi + 104], xmm7
    BZ_LERP xmm0, xmm2, xmm8            ; a = lerp(p0, p1)
    BZ_LERP xmm1, xmm3, xmm8
    BZ_LERP xmm2, xmm4, xmm8            ; b = lerp(p1, p2)
    BZ_LERP xmm3, xmm5, xmm8
    BZ_LERP xmm4, xmm6, xmm8            ; c = lerp(p2, p3)
    BZ_LERP xmm5, xmm7, xmm8
    movsd [rsi + 16], xmm0
    movsd [rsi + 24], xmm1
    movsd [rsi + 80], xmm4
    movsd [rsi + 88], xmm5
    BZ_LERP xmm0, xmm2, xmm8            ; d = lerp(a, b)
    BZ_LERP xmm1, xmm3, xmm8
    BZ_LERP xmm2, xmm4, xmm8            ; e = lerp(b, c)
    BZ_LERP xmm3, xmm5, xmm8
    movsd [rsi + 32], xmm0
    movsd [rsi + 40], xmm1
    movsd [rsi + 64], xmm2
    movsd [rsi + 72], xmm3
    BZ_LERP xmm0, xmm2, xmm8            ; B = lerp(d, e)
    BZ_LERP xmm1, xmm3, xmm8
    movsd [rsi + 48], xmm0
    movsd [rsi + 56], xmm1
    ret

; xmm0 = n (non-negative, may be NaN/inf) -> rax = clamp(ceil(n), 1, max)
bezier_ceil_count:
    ucomisd xmm0, xmm0
    jp .one
    movsd xmm1, [rel bezier_max_seg]
    ucomisd xmm0, xmm1
    jae .max
    movsd xmm1, [rel bezier_one]
    ucomisd xmm0, xmm1
    jbe .one
    cvttsd2si rax, xmm0
    cvtsi2sd xmm1, rax
    ucomisd xmm1, xmm0
    jae .done
    inc rax                             ; ceil of a non-integer
.done:
    ret
.one:
    mov eax, 1
    ret
.max:
    mov eax, UMATH_BEZIER_MAX_SEGMENTS
    ret

; xmm0 = tol -> ZF/CF set as for "tol <= 0 or NaN" (jbe skips), xmm0 kept
%macro BZ_CHECK_TOL 1
    xorpd xmm7, xmm7
    ucomisd xmm0, xmm7
    jp %1
    jbe %1
%endmacro

; -----------------------------------------------------------------------------
; size_t umath_bezier_quad_segments(const double p[6], double tol)
; -----------------------------------------------------------------------------
global umath_bezier_quad_segments
umath_bezier_quad_segments:
    BZ_CHECK_TOL .one
    movapd xmm6, xmm0
    ; d = p0 - 2 p1 + p2
    movsd xmm1, [rdi + 16]
    addsd xmm1, xmm1
    movsd xmm2, [rdi]
    subsd xmm2, xmm1
    addsd xmm2, [rdi + 32]
    movsd xmm1, [rdi + 24]
    addsd xmm1, xmm1
    movsd xmm3, [rdi + 8]
    subsd xmm3, xmm1
    addsd xmm3, [rdi + 40]
    mulsd xmm2, xmm2
    mulsd xmm3, xmm3
    addsd xmm2, xmm3
    sqrtsd xmm0, xmm2                   ; L
    mulsd xmm0, [rel bezier_quarter]
    divsd xmm0, xmm6
    sqrtsd xmm0, xmm0
    jmp bezier_ceil_count
.one:
    mov eax, 1
    ret

; -----------------------------------------------------------------------------
; size_t umath_bezier_cubic_segments(const double p[8], double tol)
; -----------------------------------------------------------------------------
global umath_bezier_cubic_segments
umath_bezier_cubic_segments:
    BZ_CHECK_TOL .one
    movapd xmm6, xmm0
    ; d1 = p0 - 2 p1 + p2
    movsd xmm1, [rdi + 16]
    addsd xmm1, xmm1
    movsd xmm2, [rdi]
    subsd xmm2, xmm1
    addsd xmm2, [rdi + 32]
    movsd xmm1, [rdi + 24]
    addsd xmm1, xmm1
    movsd xmm3, [rdi + 8]
    subsd xmm3, xmm1
    addsd xmm3, [rdi + 40]
    mulsd xmm2, xmm2
    mulsd xmm3, xmm3
    addsd xmm2, xmm3                    ; |d1|^2
    ; d2 = p1 - 2 p2 + p3
    movsd xmm1, [rdi + 32]
    addsd xmm1, xmm1
    movsd xmm4, [rdi + 16]
    subsd xmm4, xmm1
    addsd xmm4, [rdi + 48]
    movsd xmm1, [rdi + 40]
    addsd xmm1, xmm1
    movsd xmm5, [rdi + 24]
    subsd xmm5, xmm1
    addsd xmm5, [rdi + 56]
    mulsd xmm4, xmm4
    mulsd xmm5, xmm5
    addsd xmm4, xmm5                    ; |d2|^2
    maxsd xmm2, xmm4
    sqrtsd xmm0, xmm2                   ; L
    mulsd xmm0, [rel bezier_three_qtr]
    divsd xmm0, xmm6
    sqrtsd xmm0, xmm0
    jmp bezier_ceil_count
.one:
    mov eax, 1
    ret

%endif ; GUARD_LIB_UMATH_GEOM_BEZIER_ASM
