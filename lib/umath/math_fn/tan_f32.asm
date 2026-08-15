%ifndef GUARD_LIB_UMATH_MATH_FN_TAN_F32_ASM
%define GUARD_LIB_UMATH_MATH_FN_TAN_F32_ASM
; =============================================================================
; umath - unified math library
; math_fn/tan_f32.asm - single-precision tangent
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; tan(x) = sin(x) / cos(x), composed directly from umath_sin_f32 and
; umath_cos_f32 (same directory) rather than its own range reduction —
; same reasoning as pow_f32.asm composing log_f32/exp_f32: those two are
; already verified, and re-deriving tan's own polynomial buys accuracy
; this library doesn't need at the cost of a second bug-prone
; implementation of range reduction.
;
; No special-case handling for x near an odd multiple of pi/2 (where cos
; is near zero): hardware divss already does the right IEEE thing —
; divide-by-a-tiny-number produces a very large result, and an exact zero
; cos produces a signed Inf, which is the correct limiting behavior for
; tan's vertical asymptotes. NaN/Inf input already returns NaN from both
; sin_f32 and cos_f32, so it propagates here for free.
;
; x is held in xmm5 across both calls: umath_sin_f32/umath_cos_f32 use
; xmm0-4 and xmm6 internally (verified by inspection, not assumed) but
; never touch xmm5, so it survives untouched as scratch for the second
; call's input.
; =============================================================================

bits 64

section .text

; -----------------------------------------------------------------------------
; umath_tan_f32 - scalar single-precision tangent
; args:    xmm0 = input value (x), radians
; returns: xmm0 = tan(x); NaN for NaN or +/-Inf input
; -----------------------------------------------------------------------------
global umath_tan_f32
umath_tan_f32:
    movaps  xmm5, xmm0
    call    umath_sin_f32
    movaps  xmm7, xmm0            ; xmm7 = sin(x)
    movaps  xmm0, xmm5
    call    umath_cos_f32          ; xmm0 = cos(x)
    movaps  xmm1, xmm0
    movaps  xmm0, xmm7
    divss   xmm0, xmm1
    ret

; -----------------------------------------------------------------------------
; umath_tan_f32_array - tan(x) for an array of floats
; args:    rdi = destination pointer (dst)
;          rsi = source pointer (src)
;          rdx = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_tan_f32_array
umath_tan_f32_array:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done
    test    rdx, rdx
    jz      .done

.loop:
    movss   xmm0, [rsi]
    call    umath_tan_f32
    movss   [rdi], xmm0
    add     rsi, 4
    add     rdi, 4
    dec     rdx
    jnz     .loop

.done:
    ret

; -----------------------------------------------------------------------------
; umath_tan_f32_inplace - tan(x) in place for a float array
; args:    rdi = buffer pointer (buf)
;          rsi = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_tan_f32_inplace
umath_tan_f32_inplace:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done

.loop:
    movss   xmm0, [rdi]
    call    umath_tan_f32
    movss   [rdi], xmm0
    add     rdi, 4
    dec     rsi
    jnz     .loop

.done:
    ret

%endif ; GUARD_LIB_UMATH_MATH_FN_TAN_F32_ASM
