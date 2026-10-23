%ifndef GUARD_LIB_UMATH_MATH_FN_LOG1P_F64_ASM
%define GUARD_LIB_UMATH_MATH_FN_LOG1P_F64_ASM
; =============================================================================
; umath - unified math library
; math_fn/log1p_f64.asm - double-precision ln(1 + x)
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; log(1 + x) loses x's low bits when 1 + x is rounded. Goldberg's
; correction recovers them:
;
;     u = 1 + x               (rounded)
;     u == 1     ->  x        (|x| below ~2^-53, also keeps -0)
;     otherwise  ->  log(u) * (x / (u - 1))
;
; u - 1 is exact, so x / (u - 1) is exactly the factor by which rounding
; changed 1 + x, and log(u) * that factor is log(1 + x) to first order.
; With umath_log_f64 the result is a few ULP.
;
;   - x = -1 gives -Inf, x < -1 gives NaN, +Inf gives +Inf;
;   - NaN propagates (quieted).
; =============================================================================

bits 64

%include "lib/umath/math_fn/log_f64.asm"
%include "lib/umath/math_fn/loops.asm"

section .rodata
align 8
log1pf64_one:       dq 1.0
log1pf64_inf:       dq 0x7FF0000000000000

section .text

; -----------------------------------------------------------------------------
; umath_log1p_f64 - scalar ln(1 + x)
; args:    xmm0 = x
; returns: xmm0 = ln(1 + x)
; -----------------------------------------------------------------------------
global umath_log1p_f64
umath_log1p_f64:
    ucomisd xmm0, xmm0
    jp      .nan
    ucomisd xmm0, [rel log1pf64_inf]
    je      .done_noframe       ; log1p(+Inf) = +Inf
    movsd   xmm1, xmm0
    addsd   xmm1, [rel log1pf64_one]  ; u = 1 + x
    ucomisd xmm1, [rel log1pf64_one]
    je      .done_noframe       ; u == 1: the answer is x
    sub     rsp, 24
    movsd   [rsp], xmm0         ; x
    movsd   [rsp + 8], xmm1     ; u
    movapd  xmm0, xmm1
    call    umath_log_f64       ; log(u); -Inf at u = 0, NaN for u < 0
    movsd   xmm1, [rsp + 8]
    subsd   xmm1, [rel log1pf64_one]  ; u - 1, exact
    movsd   xmm2, [rsp]
    divsd   xmm2, xmm1          ; x / (u - 1)
    mulsd   xmm0, xmm2
    add     rsp, 24
.done_noframe:
    ret
.nan:
    addsd   xmm0, xmm0
    ret

mathfn_unary_arrays umath_log1p_f64, umath_log1p_f64, 8

%endif ; GUARD_LIB_UMATH_MATH_FN_LOG1P_F64_ASM
