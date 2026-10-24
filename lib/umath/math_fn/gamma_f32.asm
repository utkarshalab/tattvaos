%ifndef GUARD_LIB_UMATH_MATH_FN_GAMMA_F32_ASM
%define GUARD_LIB_UMATH_MATH_FN_GAMMA_F32_ASM
; =============================================================================
; umath - unified math library
; math_fn/gamma_f32.asm - single-precision gamma function and its logarithm
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; Widen to double (exact), call the f64 routines and round once: within
; one f32 ULP wherever the f64 result is (Gamma overflows a float from
; x ~ 35.04, which the final conversion turns into +Inf). lgamma_r's sign
; pointer (rdi) passes through. Special cases as in gamma_f64.asm.
; =============================================================================

bits 64

%include "lib/umath/math_fn/gamma_f64.asm"
%include "lib/umath/math_fn/loops.asm"

section .text

; umath_tgamma_f32 (xmm0 = x) -> xmm0
mathfn_f32_unary umath_tgamma_f32, umath_tgamma_f64
; umath_lgamma_f32 (xmm0 = x) -> xmm0
mathfn_f32_unary umath_lgamma_f32, umath_lgamma_f64
; umath_lgamma_r_f32 (xmm0 = x, rdi = int32 *sign) -> xmm0
mathfn_f32_unary umath_lgamma_r_f32, umath_lgamma_r_f64

mathfn_unary_arrays umath_tgamma_f32, umath_tgamma_f32, 4
mathfn_unary_arrays umath_lgamma_f32, umath_lgamma_f32, 4

%endif ; GUARD_LIB_UMATH_MATH_FN_GAMMA_F32_ASM
