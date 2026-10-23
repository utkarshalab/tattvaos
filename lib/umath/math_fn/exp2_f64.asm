%ifndef GUARD_LIB_UMATH_MATH_FN_EXP2_F64_ASM
%define GUARD_LIB_UMATH_MATH_FN_EXP2_F64_ASM
; =============================================================================
; umath - unified math library
; math_fn/exp2_f64.asm - double-precision 2^x
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; 2^x = 2^k * e^(r*ln2) with k = round(x) and r = x - k. Unlike
; exp(x*ln2), which multiplies x's full magnitude by a rounded ln2 (an error
; growing with |x|: ~700 ULP near x = 1000), the reduction here is exact:
; x - round(x) needs no rounding, and r*ln2 lies in [-0.35, 0.35], where
; the single rounding of the product is negligible. e^(r*ln2) comes from
; umath_exp_f64, 2^k from umath_scalbn_f64 (exact, or one rounding into the
; subnormal range).
;
;   - integer x gives exactly 2^x (r = 0, e^0 = 1);
;   - x >= 1024 overflows to +Inf, x <= -1075 underflows to +0;
;   - +-Inf give +Inf / +0, NaN propagates (quieted).
;
; Input is clamped to [-1100, 1100] first, so k always fits scalbn's range
; and the clamp cannot change the result.
; =============================================================================

bits 64

%include "lib/umath/math_fn/exp_f64.asm"
%include "lib/umath/math_fn/scalbn_f64.asm"
%include "lib/umath/math_fn/loops.asm"
%include "lib/umath/cpuid/fallback.asm"

section .rodata
align 8
exp2f64_max:    dq 1100.0
exp2f64_min:    dq -1100.0
exp2f64_ln2:    dq 0.6931471805599453

section .text

; -----------------------------------------------------------------------------
; umath_exp2_f64 - scalar 2^x
; args:    xmm0 = x
; returns: xmm0 = 2^x
; -----------------------------------------------------------------------------
global umath_exp2_f64
umath_exp2_f64:
    ucomisd xmm0, xmm0
    jp      .nan
    sub     rsp, 24
    movsd   xmm1, [rel exp2f64_max]
    minsd   xmm1, xmm0
    movsd   xmm0, [rel exp2f64_min]
    maxsd   xmm0, xmm1          ; x clamped to [-1100, 1100]
    um_roundsd xmm1, xmm0, 0    ; k = round(x), ties to even
    subsd   xmm0, xmm1          ; r = x - k, exact
    cvttsd2si rax, xmm1         ; k is integral: truncation is exact
    mov     [rsp], rax
    mulsd   xmm0, [rel exp2f64_ln2]
    call    umath_exp_f64       ; e^(r*ln2), in [0.70, 1.42]
    mov     rdi, [rsp]
    call    umath_scalbn_f64    ; * 2^k
    add     rsp, 24
    ret
.nan:
    addsd   xmm0, xmm0          ; quiet the NaN
    ret

mathfn_unary_arrays umath_exp2_f64, umath_exp2_f64, 8

%endif ; GUARD_LIB_UMATH_MATH_FN_EXP2_F64_ASM
