%ifndef GUARD_LIB_UMATH_MATH_FN_CBRT_F32_ASM
%define GUARD_LIB_UMATH_MATH_FN_CBRT_F32_ASM
; =============================================================================
; umath - unified math library
; math_fn/cbrt_f32.asm - single-precision cube root
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; Widens to double (exact), calls umath_cbrt_f64 and rounds once, so the
; result is within one f32 ULP and every special case behaves as in
; cbrt_f64.asm. The array/inplace variants call the scalar per element
; (math_fn/loops.asm), so they return exactly what umath_cbrt_f32 does.
; =============================================================================

bits 64

%include "lib/umath/math_fn/cbrt_f64.asm"
%include "lib/umath/math_fn/loops.asm"

section .text

; -----------------------------------------------------------------------------
; umath_cbrt_f32 - scalar cube root
; args:    xmm0 = x (f32)
; returns: xmm0 = result (f32)
; -----------------------------------------------------------------------------
mathfn_f32_unary umath_cbrt_f32, umath_cbrt_f64

mathfn_unary_arrays umath_cbrt_f32, umath_cbrt_f32, 4

%endif ; GUARD_LIB_UMATH_MATH_FN_CBRT_F32_ASM
