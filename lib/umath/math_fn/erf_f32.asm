%ifndef GUARD_LIB_UMATH_MATH_FN_ERF_F32_ASM
%define GUARD_LIB_UMATH_MATH_FN_ERF_F32_ASM
; =============================================================================
; umath - unified math library
; math_fn/erf_f32.asm - single-precision erf and erfc
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; Widen to double (exact), call umath_erf_f64 / umath_erfc_f64 and round
; once: within one f32 ULP, special cases as in erf_f64.asm. Array/inplace
; variants come from math_fn/loops.asm.
; =============================================================================

bits 64

%include "lib/umath/math_fn/erf_f64.asm"
%include "lib/umath/math_fn/loops.asm"

section .text

; umath_erf_f32 (xmm0 = x) -> xmm0
mathfn_f32_unary umath_erf_f32, umath_erf_f64
; umath_erfc_f32 (xmm0 = x) -> xmm0
mathfn_f32_unary umath_erfc_f32, umath_erfc_f64

mathfn_unary_arrays umath_erf_f32, umath_erf_f32, 4
mathfn_unary_arrays umath_erfc_f32, umath_erfc_f32, 4

%endif ; GUARD_LIB_UMATH_MATH_FN_ERF_F32_ASM
