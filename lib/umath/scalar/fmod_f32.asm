%ifndef GUARD_LIB_UMATH_SCALAR_FMOD_F32_ASM
%define GUARD_LIB_UMATH_SCALAR_FMOD_F32_ASM
; =============================================================================
; umath - unified math library
; scalar/fmod_f32.asm - exact floating-point remainders for floats
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; umath_fmod_f32, umath_remainder_f32 and umath_remquo_f32 widen to double
; and call the f64 routines (fmod_f64.asm). Widening is exact, the f64
; result is exact, and the remainder of two floats is itself a float, so
; the final conversion is exact too: these are exact, like the f64 ones.
; remquo's quo pointer (rdi) passes through unchanged.
; =============================================================================

bits 64

%include "lib/umath/scalar/fmod_f64.asm"
%include "lib/umath/math_fn/loops.asm"

section .text

; umath_fmod_f32 (xmm0 = x, xmm1 = y) -> xmm0
mathfn_f32_binary umath_fmod_f32, umath_fmod_f64
; umath_remainder_f32 (xmm0 = x, xmm1 = y) -> xmm0
mathfn_f32_binary umath_remainder_f32, umath_remainder_f64
; umath_remquo_f32 (xmm0 = x, xmm1 = y, rdi = int32 *quo) -> xmm0
mathfn_f32_binary umath_remquo_f32, umath_remquo_f64

mathfn_binary_arrays umath_fmod_f32, umath_fmod_f32, 4
mathfn_binary_arrays umath_remainder_f32, umath_remainder_f32, 4

%endif ; GUARD_LIB_UMATH_SCALAR_FMOD_F32_ASM
