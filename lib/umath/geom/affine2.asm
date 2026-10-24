%ifndef GUARD_LIB_UMATH_GEOM_AFFINE2_ASM
%define GUARD_LIB_UMATH_GEOM_AFFINE2_ASM
; =============================================================================
; umath - unified math library
; geom/affine2.asm - 2D affine transforms (f64)
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; A transform is six doubles m = {a, b, c, d, e, f} (48 bytes) mapping
;
;       x' = a*x + c*y + e          | a  c  e |
;       y' = b*x + d*y + f          | b  d  f |
;                                   | 0  0  1 |
;
; Composition: umath_affine2_multiply(out, m1, m2) computes out = m1 * m2,
; i.e. a point is transformed by m2 first, then by m1. `out` may alias
; either input. Points are passed as (x, y) in xmm0/xmm1 and returned the
; same way (a struct of two doubles under the System V ABI).
; =============================================================================

bits 64

%include "lib/umath/math_fn/sin_f64.asm"
%include "lib/umath/math_fn/cos_f64.asm"
%include "lib/umath/math_fn/tan_f64.asm"

section .rodata
align 8
affine2_one:    dq 1.0

section .text

; -----------------------------------------------------------------------------
; umath_affine2_identity(double out[6])
; -----------------------------------------------------------------------------
global umath_affine2_identity
umath_affine2_identity:
    movsd xmm0, [rel affine2_one]
    xorpd xmm1, xmm1
    movsd [rdi], xmm0
    movsd [rdi + 8], xmm1
    movsd [rdi + 16], xmm1
    movsd [rdi + 24], xmm0
    movsd [rdi + 32], xmm1
    movsd [rdi + 40], xmm1
    ret

; -----------------------------------------------------------------------------
; umath_affine2_translate(double out[6], double tx, double ty)
; -----------------------------------------------------------------------------
global umath_affine2_translate
umath_affine2_translate:
    movsd xmm2, [rel affine2_one]
    xorpd xmm3, xmm3
    movsd [rdi], xmm2
    movsd [rdi + 8], xmm3
    movsd [rdi + 16], xmm3
    movsd [rdi + 24], xmm2
    movsd [rdi + 32], xmm0
    movsd [rdi + 40], xmm1
    ret

; -----------------------------------------------------------------------------
; umath_affine2_scale(double out[6], double sx, double sy)
; -----------------------------------------------------------------------------
global umath_affine2_scale
umath_affine2_scale:
    xorpd xmm2, xmm2
    movsd [rdi], xmm0
    movsd [rdi + 8], xmm2
    movsd [rdi + 16], xmm2
    movsd [rdi + 24], xmm1
    movsd [rdi + 32], xmm2
    movsd [rdi + 40], xmm2
    ret

; -----------------------------------------------------------------------------
; umath_affine2_rotate(double out[6], double radians)
;   Positive angles turn +x towards +y (clockwise on a y-down screen).
; -----------------------------------------------------------------------------
global umath_affine2_rotate
umath_affine2_rotate:
    push rbx
    sub rsp, 32
    mov rbx, rdi
    movsd [rsp], xmm0
    call umath_cos_f64
    movsd [rsp + 8], xmm0               ; cos
    movsd xmm0, [rsp]
    call umath_sin_f64                  ; sin
    movsd xmm1, [rsp + 8]
    movsd [rbx], xmm1                   ; a = cos
    movsd [rbx + 8], xmm0               ; b = sin
    movapd xmm2, xmm0
    xorpd xmm3, xmm3
    subsd xmm3, xmm2
    movsd [rbx + 16], xmm3              ; c = -sin
    movsd [rbx + 24], xmm1              ; d = cos
    xorpd xmm2, xmm2
    movsd [rbx + 32], xmm2
    movsd [rbx + 40], xmm2
    add rsp, 32
    pop rbx
    ret

; -----------------------------------------------------------------------------
; umath_affine2_skew(double out[6], double angle_x, double angle_y)
;   x' = x + tan(angle_x) * y,   y' = tan(angle_y) * x + y
; -----------------------------------------------------------------------------
global umath_affine2_skew
umath_affine2_skew:
    push rbx
    sub rsp, 32
    mov rbx, rdi
    movsd [rsp], xmm1
    call umath_tan_f64
    movsd [rsp + 8], xmm0               ; tan(angle_x)
    movsd xmm0, [rsp]
    call umath_tan_f64                  ; tan(angle_y)
    movsd xmm2, [rel affine2_one]
    movsd [rbx], xmm2
    movsd [rbx + 8], xmm0               ; b = tan(angle_y)
    movsd xmm1, [rsp + 8]
    movsd [rbx + 16], xmm1              ; c = tan(angle_x)
    movsd [rbx + 24], xmm2
    xorpd xmm3, xmm3
    movsd [rbx + 32], xmm3
    movsd [rbx + 40], xmm3
    add rsp, 32
    pop rbx
    ret

; -----------------------------------------------------------------------------
; umath_affine2_multiply(double out[6], const double m1[6], const double m2[6])
;   out = m1 * m2 (apply m2, then m1); out may alias m1 or m2.
; -----------------------------------------------------------------------------
global umath_affine2_multiply
umath_affine2_multiply:
    ; a = a1*a2 + c1*b2
    movsd xmm0, [rsi]
    mulsd xmm0, [rdx]
    movsd xmm1, [rsi + 16]
    mulsd xmm1, [rdx + 8]
    addsd xmm0, xmm1
    ; b = b1*a2 + d1*b2
    movsd xmm2, [rsi + 8]
    mulsd xmm2, [rdx]
    movsd xmm1, [rsi + 24]
    mulsd xmm1, [rdx + 8]
    addsd xmm2, xmm1
    ; c = a1*c2 + c1*d2
    movsd xmm3, [rsi]
    mulsd xmm3, [rdx + 16]
    movsd xmm1, [rsi + 16]
    mulsd xmm1, [rdx + 24]
    addsd xmm3, xmm1
    ; d = b1*c2 + d1*d2
    movsd xmm4, [rsi + 8]
    mulsd xmm4, [rdx + 16]
    movsd xmm1, [rsi + 24]
    mulsd xmm1, [rdx + 24]
    addsd xmm4, xmm1
    ; e = a1*e2 + c1*f2 + e1
    movsd xmm5, [rsi]
    mulsd xmm5, [rdx + 32]
    movsd xmm1, [rsi + 16]
    mulsd xmm1, [rdx + 40]
    addsd xmm5, xmm1
    addsd xmm5, [rsi + 32]
    ; f = b1*e2 + d1*f2 + f1
    movsd xmm6, [rsi + 8]
    mulsd xmm6, [rdx + 32]
    movsd xmm1, [rsi + 24]
    mulsd xmm1, [rdx + 40]
    addsd xmm6, xmm1
    addsd xmm6, [rsi + 40]
    movsd [rdi], xmm0
    movsd [rdi + 8], xmm2
    movsd [rdi + 16], xmm3
    movsd [rdi + 24], xmm4
    movsd [rdi + 32], xmm5
    movsd [rdi + 40], xmm6
    ret

; -----------------------------------------------------------------------------
; double umath_affine2_determinant(const double m[6])   -> a*d - b*c
; -----------------------------------------------------------------------------
global umath_affine2_determinant
umath_affine2_determinant:
    movsd xmm0, [rdi]
    mulsd xmm0, [rdi + 24]
    movsd xmm1, [rdi + 8]
    mulsd xmm1, [rdi + 16]
    subsd xmm0, xmm1
    ret

; -----------------------------------------------------------------------------
; int umath_affine2_invert(double out[6], const double m[6])
;   -> 0 on success, -1 if m is singular or not finite (out untouched).
;   out may alias m.
; -----------------------------------------------------------------------------
global umath_affine2_invert
umath_affine2_invert:
    movsd xmm0, [rsi]
    mulsd xmm0, [rsi + 24]
    movsd xmm1, [rsi + 8]
    mulsd xmm1, [rsi + 16]
    subsd xmm0, xmm1                    ; det
    xorpd xmm1, xmm1
    ucomisd xmm0, xmm1
    jp .singular                        ; NaN
    je .singular                        ; zero
    movsd xmm7, [rel affine2_one]
    divsd xmm7, xmm0                    ; 1 / det
    ucomisd xmm7, xmm7
    jp .singular
    movsd xmm1, [rsi]                   ; a
    movsd xmm2, [rsi + 8]               ; b
    movsd xmm3, [rsi + 16]              ; c
    movsd xmm4, [rsi + 24]              ; d
    movsd xmm5, [rsi + 32]              ; e
    movsd xmm6, [rsi + 40]              ; f
    ; a' = d / det, b' = -b / det, c' = -c / det, d' = a / det
    movapd xmm8, xmm4
    mulsd xmm8, xmm7
    xorpd xmm9, xmm9
    subsd xmm9, xmm2
    mulsd xmm9, xmm7
    xorpd xmm10, xmm10
    subsd xmm10, xmm3
    mulsd xmm10, xmm7
    movapd xmm11, xmm1
    mulsd xmm11, xmm7
    ; e' = (c*f - d*e) / det,  f' = (b*e - a*f) / det
    movapd xmm12, xmm3
    mulsd xmm12, xmm6
    movapd xmm0, xmm4
    mulsd xmm0, xmm5
    subsd xmm12, xmm0
    mulsd xmm12, xmm7
    movapd xmm13, xmm2
    mulsd xmm13, xmm5
    movapd xmm0, xmm1
    mulsd xmm0, xmm6
    subsd xmm13, xmm0
    mulsd xmm13, xmm7
    movsd [rdi], xmm8
    movsd [rdi + 8], xmm9
    movsd [rdi + 16], xmm10
    movsd [rdi + 24], xmm11
    movsd [rdi + 32], xmm12
    movsd [rdi + 40], xmm13
    xor eax, eax
    ret
.singular:
    mov eax, -1
    ret

; -----------------------------------------------------------------------------
; (x', y') = umath_affine2_apply(const double m[6], double x, double y)
; -----------------------------------------------------------------------------
global umath_affine2_apply
umath_affine2_apply:
    movapd xmm2, xmm0
    movapd xmm3, xmm1
    movsd xmm0, [rdi]
    mulsd xmm0, xmm2
    movsd xmm4, [rdi + 16]
    mulsd xmm4, xmm3
    addsd xmm0, xmm4
    addsd xmm0, [rdi + 32]
    movsd xmm1, [rdi + 8]
    mulsd xmm1, xmm2
    movsd xmm4, [rdi + 24]
    mulsd xmm4, xmm3
    addsd xmm1, xmm4
    addsd xmm1, [rdi + 40]
    ret

; -----------------------------------------------------------------------------
; (x', y') = umath_affine2_apply_vector(const double m[6], double x, double y)
;   Like apply, without the translation (for directions and offsets).
; -----------------------------------------------------------------------------
global umath_affine2_apply_vector
umath_affine2_apply_vector:
    movapd xmm2, xmm0
    movapd xmm3, xmm1
    movsd xmm0, [rdi]
    mulsd xmm0, xmm2
    movsd xmm4, [rdi + 16]
    mulsd xmm4, xmm3
    addsd xmm0, xmm4
    movsd xmm1, [rdi + 8]
    mulsd xmm1, xmm2
    movsd xmm4, [rdi + 24]
    mulsd xmm4, xmm3
    addsd xmm1, xmm4
    ret

; -----------------------------------------------------------------------------
; umath_affine2_apply_array(const double m[6], double *dst, const double *src,
;                           size_t n)
;   Transforms n (x, y) pairs; dst may equal src.
; -----------------------------------------------------------------------------
global umath_affine2_apply_array
umath_affine2_apply_array:
    test rcx, rcx
    jz .done
    movsd xmm8, [rdi]
    movsd xmm9, [rdi + 8]
    movsd xmm10, [rdi + 16]
    movsd xmm11, [rdi + 24]
    movsd xmm12, [rdi + 32]
    movsd xmm13, [rdi + 40]
.loop:
    movsd xmm2, [rdx]
    movsd xmm3, [rdx + 8]
    movapd xmm0, xmm8
    mulsd xmm0, xmm2
    movapd xmm4, xmm10
    mulsd xmm4, xmm3
    addsd xmm0, xmm4
    addsd xmm0, xmm12
    movapd xmm1, xmm9
    mulsd xmm1, xmm2
    movapd xmm4, xmm11
    mulsd xmm4, xmm3
    addsd xmm1, xmm4
    addsd xmm1, xmm13
    movsd [rsi], xmm0
    movsd [rsi + 8], xmm1
    add rdx, 16
    add rsi, 16
    dec rcx
    jnz .loop
.done:
    ret

%endif ; GUARD_LIB_UMATH_GEOM_AFFINE2_ASM
