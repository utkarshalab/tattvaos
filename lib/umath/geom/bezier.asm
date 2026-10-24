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
;   bounds    the tight box (min x, min y, max x, max y) of the curve for t in
;             [0, 1]: the end points and, per axis, the curve at the roots of
;             B'(t) inside (0, 1) - quad t = (p0 - p1) / (p0 - 2p1 + p2), cubic
;             the roots of A t^2 + B t + C with c0 = p1 - p0, c1 = p2 - p1,
;             c2 = p3 - p2, A = c0 - 2c1 + c2, B = 2 (c1 - c0), C = c0
;             (B / 3 of the derivative), evaluated by the same lerps as eval.
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
bezier_half:        dq 0.5
bezier_zero:        dq 0.0

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

; -----------------------------------------------------------------------------
; umath_bezier_quad_bounds(const double p[6], double out[4])
;   out = min x, min y, max x, max y of the quadratic for t in [0, 1]
; -----------------------------------------------------------------------------
global umath_bezier_quad_bounds
umath_bezier_quad_bounds:
    xor ecx, ecx                        ; axis: 0 x, 8 y
.axis:
    movsd xmm0, [rdi + rcx]             ; p0
    movsd xmm1, [rdi + rcx + 16]        ; p1
    movsd xmm2, [rdi + rcx + 32]        ; p2
    movapd xmm4, xmm0                   ; min
    minsd xmm4, xmm2
    movapd xmm5, xmm0                   ; max
    maxsd xmm5, xmm2
    ; t = (p0 - p1) / (p0 - 2 p1 + p2)
    movapd xmm6, xmm1
    addsd xmm6, xmm6
    movapd xmm7, xmm0
    subsd xmm7, xmm6
    addsd xmm7, xmm2                    ; denominator
    xorpd xmm6, xmm6
    ucomisd xmm7, xmm6
    jp .store
    je .store
    movapd xmm3, xmm0
    subsd xmm3, xmm1
    divsd xmm3, xmm7                    ; t
    call bezier_bounds_inside
    jbe .store
    ; q0 = lerp(p0, p1), q1 = lerp(p1, p2), v = lerp(q0, q1)
    movapd xmm6, xmm1
    subsd xmm6, xmm0
    mulsd xmm6, xmm3
    addsd xmm6, xmm0                    ; q0
    movapd xmm7, xmm2
    subsd xmm7, xmm1
    mulsd xmm7, xmm3
    addsd xmm7, xmm1                    ; q1
    subsd xmm7, xmm6
    mulsd xmm7, xmm3
    addsd xmm6, xmm7                    ; v
    minsd xmm4, xmm6
    maxsd xmm5, xmm6
.store:
    movsd [rsi + rcx], xmm4
    movsd [rsi + rcx + 16], xmm5
    add ecx, 8
    cmp ecx, 16
    jb .axis
    ret

; xmm3 = t -> flags: "ja" when 0 < t < 1 (NaN: not inside). Keeps xmm3.
bezier_bounds_inside:
    xorpd xmm6, xmm6
    ucomisd xmm3, xmm6
    jp .no
    jbe .no
    movsd xmm6, [rel bezier_one]
    ucomisd xmm6, xmm3                  ; 1 > t: "ja"
    ret
.no:
    xorpd xmm6, xmm6
    ucomisd xmm6, xmm6                  ; ZF = 1: "jbe" taken
    ret

; -----------------------------------------------------------------------------
; umath_bezier_cubic_bounds(const double p[8], double out[4])
;   out = min x, min y, max x, max y of the cubic for t in [0, 1]
; -----------------------------------------------------------------------------
global umath_bezier_cubic_bounds
umath_bezier_cubic_bounds:
    push rbx
    sub rsp, 64
    xor ebx, ebx                        ; axis: 0 x, 8 y
.axis:
    movsd xmm0, [rdi + rbx]
    movsd xmm1, [rdi + rbx + 16]
    movsd xmm2, [rdi + rbx + 32]
    movsd xmm3, [rdi + rbx + 48]
    movsd [rsp], xmm0                   ; p0 .. p3
    movsd [rsp + 8], xmm1
    movsd [rsp + 16], xmm2
    movsd [rsp + 24], xmm3
    movapd xmm4, xmm0
    minsd xmm4, xmm3
    movapd xmm5, xmm0
    maxsd xmm5, xmm3
    movsd [rsp + 32], xmm4              ; min
    movsd [rsp + 40], xmm5              ; max
    ; c0, c1, c2 and A, B, C
    subsd xmm3, xmm2                    ; c2 = p3 - p2
    subsd xmm2, xmm1                    ; c1 = p2 - p1
    subsd xmm1, xmm0                    ; c0 = p1 - p0 = C
    movapd xmm4, xmm2
    addsd xmm4, xmm4
    movapd xmm6, xmm1
    subsd xmm6, xmm4
    addsd xmm6, xmm3                    ; A = c0 - 2 c1 + c2
    movapd xmm7, xmm2
    subsd xmm7, xmm1
    addsd xmm7, xmm7                    ; B = 2 (c1 - c0)
    xorpd xmm4, xmm4
    ucomisd xmm6, xmm4
    jp .done_axis
    jne .quadratic
    ; A = 0: t = -C / B
    ucomisd xmm7, xmm4
    jp .done_axis
    je .done_axis
    xorpd xmm3, xmm3
    subsd xmm3, xmm1
    divsd xmm3, xmm7
    call .try
    jmp .done_axis
.quadratic:
    ; disc = B^2 - 4 A C
    movapd xmm2, xmm7
    mulsd xmm2, xmm7
    movapd xmm3, xmm6
    mulsd xmm3, xmm1
    addsd xmm3, xmm3
    addsd xmm3, xmm3
    subsd xmm2, xmm3
    ucomisd xmm2, xmm4
    jp .done_axis
    jb .done_axis
    sqrtsd xmm2, xmm2
    addsd xmm6, xmm6                    ; 2 A
    movsd [rsp + 48], xmm6
    movsd [rsp + 56], xmm2
    ; (-B + s) / 2A
    xorpd xmm3, xmm3
    subsd xmm3, xmm7
    movapd xmm0, xmm3
    addsd xmm3, xmm2
    divsd xmm3, xmm6
    movsd [rsp + 48], xmm6
    movapd xmm6, xmm0                   ; -B
    subsd xmm6, xmm2
    divsd xmm6, [rsp + 48]              ; (-B - s) / 2A
    movsd [rsp + 56], xmm6
    call .try
    movsd xmm3, [rsp + 56]
    call .try
.done_axis:
    movsd xmm4, [rsp + 32]
    movsd xmm5, [rsp + 40]
    movsd [rsi + rbx], xmm4
    movsd [rsi + rbx + 16], xmm5
    add ebx, 8
    cmp ebx, 16
    jb .axis
    add rsp, 64
    pop rbx
    ret
; xmm3 = t: inside (0, 1), the curve there widens the box (frame at rsp + 8)
.try:
    call bezier_bounds_inside
    jbe .try_out
    movsd xmm0, [rsp + 8]               ; p0 .. p3
    movsd xmm1, [rsp + 16]
    movsd xmm2, [rsp + 24]
    movsd xmm4, [rsp + 32]
    ; de Casteljau, as eval: lerp(a, b) = a + (b - a) t
    movapd xmm5, xmm1
    subsd xmm5, xmm0
    mulsd xmm5, xmm3
    addsd xmm0, xmm5                    ; a = lerp(p0, p1)
    movapd xmm5, xmm2
    subsd xmm5, xmm1
    mulsd xmm5, xmm3
    addsd xmm1, xmm5                    ; b = lerp(p1, p2)
    movapd xmm5, xmm4
    subsd xmm5, xmm2
    mulsd xmm5, xmm3
    addsd xmm2, xmm5                    ; c = lerp(p2, p3)
    movapd xmm5, xmm1
    subsd xmm5, xmm0
    mulsd xmm5, xmm3
    addsd xmm0, xmm5                    ; d = lerp(a, b)
    movapd xmm5, xmm2
    subsd xmm5, xmm1
    mulsd xmm5, xmm3
    addsd xmm1, xmm5                    ; e = lerp(b, c)
    movapd xmm5, xmm1
    subsd xmm5, xmm0
    mulsd xmm5, xmm3
    addsd xmm0, xmm5                    ; v = lerp(d, e)
    movsd xmm4, [rsp + 8 + 32]
    minsd xmm4, xmm0
    movsd [rsp + 8 + 32], xmm4
    movsd xmm5, [rsp + 8 + 40]
    maxsd xmm5, xmm0
    movsd [rsp + 8 + 40], xmm5
.try_out:
    ret

%endif ; GUARD_LIB_UMATH_GEOM_BEZIER_ASM
