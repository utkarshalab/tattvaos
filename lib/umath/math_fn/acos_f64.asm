%ifndef GUARD_LIB_UMATH_MATH_FN_ACOS_F64_ASM
%define GUARD_LIB_UMATH_MATH_FN_ACOS_F64_ASM
; =============================================================================
; umath - unified math library
; math_fn/acos_f64.asm - double-precision arccosine
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; acos(x) = 2 * atan(sqrt((1 - x) / (1 + x))), valid on (-1, 1].
; Each factor is cancellation-free where it matters: near x = 1, 1 - x is
; exact (Sterbenz) and the small result keeps full relative accuracy;
; near x = -1, 1 + x is exact and the large ratio is folded by
; atanf64__core into pi/2 - atan(..). Doubling is exact.
;
;   - x = 1 gives +0, x = -1 gives pi, |x| > 1 gives NaN;
;   - NaN propagates (quieted).
; =============================================================================

bits 64

%include "lib/umath/math_fn/atan_f64.asm"
%include "lib/umath/math_fn/loops.asm"

section .rodata
align 8
acosf64_one:        dq 1.0
acosf64_pi:         dq 0x400921FB54442D18
acosf64_nan:        dq 0x7FF8000000000000
align 16                                        ; andpd memory operand
acosf64_abs:        dq 0x7FFFFFFFFFFFFFFF, 0x7FFFFFFFFFFFFFFF

section .text

; -----------------------------------------------------------------------------
; umath_acos_f64 - scalar arccosine
; args:    xmm0 = x
; returns: xmm0 = acos(x), in [0, pi]
; -----------------------------------------------------------------------------
global umath_acos_f64
umath_acos_f64:
    ucomisd xmm0, xmm0
    jp      .nan
    movapd  xmm1, xmm0
    andpd   xmm1, [rel acosf64_abs]
    comisd  xmm1, [rel acosf64_one]
    ja      .domain
    movsd   xmm1, [rel acosf64_one]
    addsd   xmm1, xmm0          ; 1 + x
    xorpd   xmm2, xmm2
    ucomisd xmm1, xmm2
    je      .pi                 ; x = -1
    movsd   xmm2, [rel acosf64_one]
    subsd   xmm2, xmm0          ; 1 - x
    divsd   xmm2, xmm1
    sqrtsd  xmm0, xmm2
    call    atanf64__core
    addsd   xmm0, xmm0
    ret
.pi:
    movsd   xmm0, [rel acosf64_pi]
    ret
.domain:
    movsd   xmm0, [rel acosf64_nan]
    ret
.nan:
    addsd   xmm0, xmm0
    ret

mathfn_unary_arrays umath_acos_f64, umath_acos_f64, 8

%endif ; GUARD_LIB_UMATH_MATH_FN_ACOS_F64_ASM
