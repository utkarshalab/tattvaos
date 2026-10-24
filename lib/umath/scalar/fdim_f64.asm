%ifndef GUARD_LIB_UMATH_SCALAR_FDIM_F64_ASM
%define GUARD_LIB_UMATH_SCALAR_FDIM_F64_ASM
; =============================================================================
; umath - unified math library
; scalar/fdim_f64.asm - positive difference for doubles
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; fdim(x, y) = x - y when x > y, +0 otherwise (C99). The subtraction
; rounds once and may overflow to +Inf; NaN in either operand gives NaN.
; =============================================================================

bits 64

%include "lib/umath/math_fn/loops.asm"

section .text

; -----------------------------------------------------------------------------
; umath_fdim_f64 - positive difference
; args:    xmm0 = x, xmm1 = y
; returns: xmm0 = max(x - y, +0), NaN if either is NaN
; -----------------------------------------------------------------------------
global umath_fdim_f64
umath_fdim_f64:
    ucomisd  xmm0, xmm1
    jp      .nan
    jbe     .zero
    subsd   xmm0, xmm1
    ret
.zero:
    xorps   xmm0, xmm0
    ret
.nan:
    addsd   xmm0, xmm1
    ret

mathfn_binary_arrays umath_fdim_f64, umath_fdim_f64, 8

%endif ; GUARD_LIB_UMATH_SCALAR_FDIM_F64_ASM
