%ifndef GUARD_LIB_UMATH_MATH_FN_ASIN_F64_ASM
%define GUARD_LIB_UMATH_MATH_FN_ASIN_F64_ASM
; =============================================================================
; umath - unified math library
; math_fn/asin_f64.asm - double-precision arcsine
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; asin(x) = atan(a / sqrt(1 - a^2)) with a = |x|, sign of x reattached.
; 1 - a^2 cancels as a approaches 1, so for a >= 0.5 it is formed as
; (1 - a) * (1 + a): 1 - a is exact there (Sterbenz), leaving two
; ordinary roundings instead of a cancellation. Near a = 1 the ratio is
; large and atanf64__core folds it to pi/2 - atan(sqrt(..)/a), which keeps
; full accuracy right up to the endpoint.
;
;   - |x| > 1 gives NaN, +-1 gives +-pi/2, +-0 gives +-0;
;   - tiny x return x (asin(x) = x to double precision below ~1.5e-8);
;   - NaN propagates (quieted).
; =============================================================================

bits 64

%include "lib/umath/math_fn/atan_f64.asm"
%include "lib/umath/math_fn/loops.asm"

section .rodata
align 8
asinf64_one:        dq 1.0
asinf64_half:       dq 0.5
asinf64_pi2:        dq 0x3FF921FB54442D18       ; pi/2
asinf64_nan:        dq 0x7FF8000000000000

section .text

; -----------------------------------------------------------------------------
; umath_asin_f64 - scalar arcsine
; args:    xmm0 = x
; returns: xmm0 = asin(x), in [-pi/2, pi/2]
; -----------------------------------------------------------------------------
global umath_asin_f64
umath_asin_f64:
    ucomisd xmm0, xmm0
    jp      .nan
    movq    rax, xmm0
    mov     r8, rax
    btr     rax, 63
    xor     r8, rax             ; sign bit of x
    movq    xmm0, rax           ; a
    comisd  xmm0, [rel asinf64_one]
    ja      .domain
    je      .one
    movsd   xmm1, [rel asinf64_one]
    comisd  xmm0, [rel asinf64_half]
    jae     .near_one
    movapd  xmm2, xmm0
    mulsd   xmm2, xmm0
    subsd   xmm1, xmm2          ; 1 - a^2
    jmp     .root
.near_one:
    subsd   xmm1, xmm0          ; 1 - a, exact
    movsd   xmm2, [rel asinf64_one]
    addsd   xmm2, xmm0          ; 1 + a
    mulsd   xmm1, xmm2
.root:
    sqrtsd  xmm1, xmm1
    divsd   xmm0, xmm1          ; a / sqrt(1 - a^2)
    call    atanf64__core
    jmp     .sign
.one:
    movsd   xmm0, [rel asinf64_pi2]
.sign:
    movq    rax, xmm0
    or      rax, r8
    movq    xmm0, rax
    ret
.domain:
    movsd   xmm0, [rel asinf64_nan]
    ret
.nan:
    addsd   xmm0, xmm0
    ret

mathfn_unary_arrays umath_asin_f64, umath_asin_f64, 8

%endif ; GUARD_LIB_UMATH_MATH_FN_ASIN_F64_ASM
