%ifndef GUARD_LIB_UMATH_MATH_FN_COSH_F64_ASM
%define GUARD_LIB_UMATH_MATH_FN_COSH_F64_ASM
; =============================================================================
; umath - unified math library
; math_fn/cosh_f64.asm - double-precision hyperbolic cosine
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; cosh(-x) = cosh(x); with a = |x|:
;
;   a < 22           e = e^a, cosh(a) = e/2 + 1/(2e) -- both terms
;                    positive, so nothing cancels (and a near 0 gives 1)
;   a < 709.7        e^a / 2
;   otherwise        w = e^(a/2), (w/2) * w -- finite up to ~710.4758
;
; +-Inf give +Inf, NaN propagates (quieted).
; =============================================================================

bits 64

%include "lib/umath/math_fn/exp_f64.asm"
%include "lib/umath/math_fn/loops.asm"

section .rodata
align 8
coshf64_22:         dq 22.0
coshf64_big:        dq 709.7
coshf64_half:       dq 0.5
align 16                                        ; andpd memory operand
coshf64_abs:        dq 0x7FFFFFFFFFFFFFFF, 0x7FFFFFFFFFFFFFFF

section .text

; -----------------------------------------------------------------------------
; umath_cosh_f64 - scalar hyperbolic cosine
; args:    xmm0 = x
; returns: xmm0 = cosh(x), >= 1
; -----------------------------------------------------------------------------
global umath_cosh_f64
umath_cosh_f64:
    ucomisd xmm0, xmm0
    jp      .nan
    andpd   xmm0, [rel coshf64_abs]
    sub     rsp, 8
    comisd  xmm0, [rel coshf64_22]
    jae     .large
    call    umath_exp_f64       ; e
    movsd   xmm1, [rel coshf64_half]
    divsd   xmm1, xmm0          ; 1/(2e)
    mulsd   xmm0, [rel coshf64_half]
    addsd   xmm0, xmm1
    add     rsp, 8
    ret
.large:
    comisd  xmm0, [rel coshf64_big]
    jae     .huge
    call    umath_exp_f64
    mulsd   xmm0, [rel coshf64_half]
    add     rsp, 8
    ret
.huge:
    mulsd   xmm0, [rel coshf64_half]
    call    umath_exp_f64
    movapd  xmm1, xmm0
    mulsd   xmm1, [rel coshf64_half]
    mulsd   xmm0, xmm1
    add     rsp, 8
    ret
.nan:
    addsd   xmm0, xmm0
    ret

mathfn_unary_arrays umath_cosh_f64, umath_cosh_f64, 8

%endif ; GUARD_LIB_UMATH_MATH_FN_COSH_F64_ASM
