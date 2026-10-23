%ifndef GUARD_LIB_UMATH_MATH_FN_ACOS_F32_ASM
%define GUARD_LIB_UMATH_MATH_FN_ACOS_F32_ASM
; =============================================================================
; umath - unified math library
; math_fn/acos_f32.asm - single-precision arccosine
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; Widens to double (exact), calls umath_acos_f64 and rounds once, so the
; result is within one f32 ULP and every special case behaves as in
; acos_f64.asm. The array/inplace variants call the scalar per element
; (math_fn/loops.asm), so they return exactly what umath_acos_f32 does.
; =============================================================================

bits 64

%include "lib/umath/math_fn/acos_f64.asm"
%include "lib/umath/math_fn/loops.asm"

section .text

; -----------------------------------------------------------------------------
; umath_acos_f32 - scalar arccosine
; args:    xmm0 = x (f32)
; returns: xmm0 = result (f32)
; -----------------------------------------------------------------------------
mathfn_f32_unary umath_acos_f32, umath_acos_f64

mathfn_unary_arrays umath_acos_f32, umath_acos_f32, 4

%endif ; GUARD_LIB_UMATH_MATH_FN_ACOS_F32_ASM
