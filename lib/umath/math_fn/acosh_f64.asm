%ifndef GUARD_LIB_UMATH_MATH_FN_ACOSH_F64_ASM
%define GUARD_LIB_UMATH_MATH_FN_ACOSH_F64_ASM
; =============================================================================
; umath - unified math library
; math_fn/acosh_f64.asm - double-precision inverse hyperbolic cosine
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; acosh(x) = ln(x + sqrt(x^2 - 1)) for x >= 1:
;
;   x <= 2           t = x - 1 (exact), log1p(t + sqrt(2t + t^2))
;                    -- x^2 - 1 cancels near 1; 2t + t^2 does not
;   x <= 2^28        ln(2x - 1 / (x + sqrt(x^2 - 1)))
;   otherwise        ln(x) + ln(2)
;
;   - x = 1 gives +0, x < 1 gives NaN, +Inf gives +Inf;
;   - NaN propagates (quieted).
; =============================================================================

bits 64

%include "lib/umath/math_fn/log_f64.asm"
%include "lib/umath/math_fn/log1p_f64.asm"
%include "lib/umath/math_fn/loops.asm"

section .rodata
align 8
acoshf64_one:       dq 1.0
acoshf64_two:       dq 2.0
acoshf64_big:       dq 0x41B0000000000000       ; 2^28
acoshf64_ln2:       dq 0.6931471805599453
acoshf64_nan:       dq 0x7FF8000000000000

section .text

; -----------------------------------------------------------------------------
; umath_acosh_f64 - scalar inverse hyperbolic cosine
; args:    xmm0 = x
; returns: xmm0 = acosh(x), >= 0
; -----------------------------------------------------------------------------
global umath_acosh_f64
umath_acosh_f64:
    ucomisd xmm0, xmm0
    jp      .nan
    comisd  xmm0, [rel acoshf64_one]
    jb      .domain
    sub     rsp, 8
    comisd  xmm0, [rel acoshf64_two]
    ja      .medium
    subsd   xmm0, [rel acoshf64_one]  ; t
    movapd  xmm1, xmm0
    mulsd   xmm1, xmm0
    movapd  xmm2, xmm0
    addsd   xmm2, xmm0
    addsd   xmm1, xmm2          ; 2t + t^2
    sqrtsd  xmm1, xmm1
    addsd   xmm0, xmm1
    call    umath_log1p_f64
    add     rsp, 8
    ret
.medium:
    comisd  xmm0, [rel acoshf64_big]
    ja      .large
    movapd  xmm1, xmm0
    mulsd   xmm1, xmm0
    subsd   xmm1, [rel acoshf64_one]
    sqrtsd  xmm1, xmm1
    addsd   xmm1, xmm0          ; x + sqrt(x^2 - 1)
    movsd   xmm2, [rel acoshf64_one]
    divsd   xmm2, xmm1
    addsd   xmm0, xmm0
    subsd   xmm0, xmm2
    call    umath_log_f64
    add     rsp, 8
    ret
.large:
    call    umath_log_f64       ; +Inf stays +Inf
    addsd   xmm0, [rel acoshf64_ln2]
    add     rsp, 8
    ret
.domain:
    movsd   xmm0, [rel acoshf64_nan]
    ret
.nan:
    addsd   xmm0, xmm0
    ret

mathfn_unary_arrays umath_acosh_f64, umath_acosh_f64, 8

%endif ; GUARD_LIB_UMATH_MATH_FN_ACOSH_F64_ASM
