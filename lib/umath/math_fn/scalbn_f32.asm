%ifndef GUARD_LIB_UMATH_MATH_FN_SCALBN_F32_ASM
%define GUARD_LIB_UMATH_MATH_FN_SCALBN_F32_ASM
; =============================================================================
; umath - unified math library
; math_fn/scalbn_f32.asm - x * 2^n for floats (scalbn / ldexp)
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; The float is widened to double (exact) and multiplied there by 2^n with
; n clamped to [-400, 400]: every float times such a power of two is a
; normal double, so the product is exact, and the one conversion back to
; float is the only rounding (subnormal results, overflow to +-Inf and
; underflow to +-0 included). Any n outside the clamp already overflows
; or underflows every nonzero float, so clamping cannot change a result.
; NaN, +-Inf and +-0 pass through.
; =============================================================================

bits 64

section .text

; -----------------------------------------------------------------------------
; umath_scalbn_f32 / umath_ldexp_f32 - x * 2^n
; args:    xmm0 = x (f32), rdi = n (signed 64-bit)
; returns: xmm0 = x * 2^n (f32)
; -----------------------------------------------------------------------------
global umath_scalbn_f32
global umath_ldexp_f32
umath_ldexp_f32:
umath_scalbn_f32:
    mov     rax, rdi
    mov     rcx, -400
    cmp     rax, rcx
    cmovl   rax, rcx
    mov     ecx, 400
    cmp     rax, rcx
    cmovg   rax, rcx
    add     rax, 1023
    shl     rax, 52
    movq    xmm1, rax           ; 2^n as a double
    cvtss2sd xmm0, xmm0
    mulsd   xmm0, xmm1          ; exact
    cvtsd2ss xmm0, xmm0         ; the only rounding
    ret

%endif ; GUARD_LIB_UMATH_MATH_FN_SCALBN_F32_ASM
