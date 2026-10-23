%ifndef GUARD_LIB_UMATH_MATH_FN_ATAN2_F64_ASM
%define GUARD_LIB_UMATH_MATH_FN_ATAN2_F64_ASM
; =============================================================================
; umath - unified math library
; math_fn/atan2_f64.asm - double-precision two-argument arctangent
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; atan2(y, x) is the angle of the point (x, y), in [-pi, pi]. The result
; takes the sign of y; its magnitude, with a = |y|, b = |x|:
;
;   y or x NaN                -> NaN
;   a = 0                     -> 0 if x is +0 or positive, pi if x is -0
;                                or negative
;   b = 0 (a != 0)            -> pi/2
;   a = Inf, b = Inf          -> pi/4 if x > 0, 3pi/4 if x < 0
;   a = Inf (b finite)        -> pi/2
;   b = Inf (a finite)        -> 0 if x > 0, pi if x < 0
;   otherwise                 -> r = atan(a / b), or pi - r if x < 0
;
; a / b may overflow to +Inf (atan gives pi/2) or underflow (atan of a
; subnormal is itself), both correct limits. pi - r is formed as
; (pi_hi - r) + pi_lo. The core is atanf64__core from atan_f64.asm.
; =============================================================================

bits 64

%include "lib/umath/math_fn/atan_f64.asm"
%include "lib/umath/math_fn/loops.asm"

section .rodata
align 8
atan2f64_pi_hi:     dq 0x400921FB54442D18
atan2f64_pi_lo:     dq 0x3CA1A62633145C07
atan2f64_pi2:       dq 0x3FF921FB54442D18       ; pi/2
atan2f64_pi4:       dq 0x3FE921FB54442D18       ; pi/4
atan2f64_3pi4:      dq 0x4002D97C7F3321D2       ; 3pi/4
atan2f64_inf_bits:  dq 0x7FF0000000000000

section .text

; -----------------------------------------------------------------------------
; umath_atan2_f64 - scalar atan2(y, x)
; args:    xmm0 = y, xmm1 = x
; returns: xmm0 = angle in [-pi, pi]
; -----------------------------------------------------------------------------
global umath_atan2_f64
umath_atan2_f64:
    ucomisd xmm0, xmm1
    jp      .nan
    movq    rax, xmm0
    mov     r8, rax
    btr     rax, 63
    xor     r8, rax             ; r8 = sign bit of y
    movq    r9, xmm1
    mov     r10, r9
    btr     r9, 63              ; r9 = bits of |x|, r10 bit 63 = sign of x
    mov     r11, [rel atan2f64_inf_bits]
    test    rax, rax
    jz      .y_zero
    test    r9, r9
    jz      .half_pi
    cmp     rax, r11
    je      .y_inf
    cmp     r9, r11
    je      .x_inf
    movq    xmm0, rax
    movq    xmm1, r9
    divsd   xmm0, xmm1          ; a / b
    call    atanf64__core
    test    r10, r10
    jns     .sign
    movsd   xmm1, [rel atan2f64_pi_hi]
    subsd   xmm1, xmm0
    addsd   xmm1, [rel atan2f64_pi_lo]
    movapd  xmm0, xmm1          ; pi - r
.sign:
    movq    rax, xmm0
    or      rax, r8
    movq    xmm0, rax
    ret
.y_zero:                        ; +-0 or +-pi
    xorpd   xmm0, xmm0
    test    r10, r10
    jns     .sign
    movsd   xmm0, [rel atan2f64_pi_hi]
    jmp     .sign
.half_pi:
    movsd   xmm0, [rel atan2f64_pi2]
    jmp     .sign
.y_inf:
    cmp     r9, r11
    jne     .half_pi
    movsd   xmm0, [rel atan2f64_pi4]
    test    r10, r10
    jns     .sign
    movsd   xmm0, [rel atan2f64_3pi4]
    jmp     .sign
.x_inf:
    xorpd   xmm0, xmm0
    test    r10, r10
    jns     .sign
    movsd   xmm0, [rel atan2f64_pi_hi]
    jmp     .sign
.nan:
    addsd   xmm0, xmm1          ; a quiet NaN
    ret

mathfn_binary_arrays umath_atan2_f64, umath_atan2_f64, 8

%endif ; GUARD_LIB_UMATH_MATH_FN_ATAN2_F64_ASM
