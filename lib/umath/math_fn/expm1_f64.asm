%ifndef GUARD_LIB_UMATH_MATH_FN_EXPM1_F64_ASM
%define GUARD_LIB_UMATH_MATH_FN_EXPM1_F64_ASM
; =============================================================================
; umath - unified math library
; math_fn/expm1_f64.asm - double-precision e^x - 1
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; exp(x) - 1 cancels catastrophically for small |x| (exp(1e-10) - 1 keeps
; only ~7 correct digits). This uses Kahan's correction:
;
;     u = exp(x)
;     u == 1          ->  x           (|x| below ~2^-54, also keeps -0)
;     u - 1 == -1     ->  -1          (x below ~-37.4)
;     otherwise       ->  (u - 1) * (x / log(u))
;
; u - 1 is exact (Sterbenz), and x / log(u) corrects for the rounding that
; produced u: log(u) is the exponent u actually represents, so the ratio
; rescales (u - 1) from that exponent back to x's. With umath_exp_f64 and
; umath_log_f64 the result is a few ULP over the whole range.
;
;   - x above ~709.78 overflows to +Inf, +Inf gives +Inf, -Inf gives -1;
;   - NaN propagates (quieted).
; =============================================================================

bits 64

%include "lib/umath/math_fn/exp_f64.asm"
%include "lib/umath/math_fn/log_f64.asm"
%include "lib/umath/math_fn/loops.asm"

section .rodata
align 8
expm1f64_one:       dq 1.0
expm1f64_m1:        dq -1.0
expm1f64_inf:       dq 0x7FF0000000000000

section .text

; -----------------------------------------------------------------------------
; umath_expm1_f64 - scalar e^x - 1
; args:    xmm0 = x
; returns: xmm0 = e^x - 1
; -----------------------------------------------------------------------------
global umath_expm1_f64
umath_expm1_f64:
    ucomisd xmm0, xmm0
    jp      .nan
    sub     rsp, 40
    movsd   [rsp], xmm0         ; x
    call    umath_exp_f64       ; u
    ucomisd xmm0, [rel expm1f64_one]
    je      .return_x
    ucomisd xmm0, [rel expm1f64_inf]
    je      .done               ; overflow: +Inf
    movsd   xmm1, xmm0
    subsd   xmm1, [rel expm1f64_one]  ; u - 1, exact
    ucomisd xmm1, [rel expm1f64_m1]
    je      .minus_one
    movsd   [rsp + 8], xmm1
    call    umath_log_f64       ; log(u)
    movsd   xmm1, [rsp]
    divsd   xmm1, xmm0          ; x / log(u)
    movsd   xmm0, [rsp + 8]
    mulsd   xmm0, xmm1
.done:
    add     rsp, 40
    ret
.return_x:
    movsd   xmm0, [rsp]
    add     rsp, 40
    ret
.minus_one:
    movsd   xmm0, [rel expm1f64_m1]
    add     rsp, 40
    ret
.nan:
    addsd   xmm0, xmm0
    ret

mathfn_unary_arrays umath_expm1_f64, umath_expm1_f64, 8

%endif ; GUARD_LIB_UMATH_MATH_FN_EXPM1_F64_ASM
