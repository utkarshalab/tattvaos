%ifndef GUARD_LIB_UMATH_SCALAR_FDIM_F32_ASM
%define GUARD_LIB_UMATH_SCALAR_FDIM_F32_ASM
; =============================================================================
; umath - unified math library
; scalar/fdim_f32.asm - positive difference for floats
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
; umath_fdim_f32 - positive difference
; args:    xmm0 = x, xmm1 = y
; returns: xmm0 = max(x - y, +0), NaN if either is NaN
; -----------------------------------------------------------------------------
global umath_fdim_f32
umath_fdim_f32:
    ucomiss  xmm0, xmm1
    jp      .nan
    jbe     .zero
    subss   xmm0, xmm1
    ret
.zero:
    xorps   xmm0, xmm0
    ret
.nan:
    addss   xmm0, xmm1
    ret

mathfn_binary_arrays umath_fdim_f32, umath_fdim_f32, 4

%endif ; GUARD_LIB_UMATH_SCALAR_FDIM_F32_ASM
