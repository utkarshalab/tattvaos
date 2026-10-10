%ifndef GUARD_LIB_UMATH_MATH_FN_POW_F32_ASM
%define GUARD_LIB_UMATH_MATH_FN_POW_F32_ASM
; =============================================================================
; umath - unified math library
; math_fn/pow_f32.asm - single-precision power function (x^y)
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; Algorithm: widen x and y to double, evaluate umath_pow_f64, and round the
; result to float once. Forming y*ln(x) in single precision would cost
; ~|y*ln(x)| ULP of float (measured ~200 ULP for results near 1e33); in
; double that error is far below float's resolution, so the result is
; within an ULP or two. Special cases are pow_f64's (see that file), which
; carry over exactly through the conversions:
;
;   - pow(x, +/-0) = 1 for any x, including NaN x; pow(1, y) = 1 for any y.
;   - NaN propagates otherwise.
;   - pow(+/-0, y>0) = +0, pow(+/-0, y<0) = +Inf; an odd integer y keeps
;     the sign of x (pow(-0, 3) = -0, pow(-0, -1) = -Inf).
;   - pow(x<0, y): integer y only (odd y negates), NaN otherwise.
;   - Results beyond FLT_MAX become +Inf and tiny results round through
;     float subnormals to 0 in the final cvtsd2ss.
; =============================================================================

bits 64

%include "lib/umath/math_fn/pow_f64.asm"

section .text

; -----------------------------------------------------------------------------
; umath_pow_f32 - scalar single-precision x^y
; args:    xmm0 = base (x)
;          xmm1 = exponent (y)
; returns: xmm0 = x^y
; -----------------------------------------------------------------------------
global umath_pow_f32
umath_pow_f32:
    sub     rsp, 8                ; keep rsp 16-byte aligned at the call
    cvtss2sd xmm0, xmm0           ; exact widening
    cvtss2sd xmm1, xmm1
    call    umath_pow_f64
    cvtsd2ss xmm0, xmm0           ; single rounding to float
    add     rsp, 8
    ret

; -----------------------------------------------------------------------------
; umath_pow_f32_array - pow(x, y) elementwise for two arrays
; args:    rdi = destination pointer (dst)
;          rsi = first operand array (xs)
;          rdx = second operand array (ys)
;          rcx = size of arrays (count)
; returns: void
;
; Pairs are widened and run through powf64__packed2, exactly what
; umath_pow_f32 does per element (widen, pow_f64, round once).
; -----------------------------------------------------------------------------
global umath_pow_f32_array
umath_pow_f32_array:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done
    test    rdx, rdx
    jz      .done
    test    rcx, rcx
    jz      .done

    mov     r10, rcx            ; count; the scalar tail clobbers rcx
    shr     rcx, 1
    jz      .tail
.loop:
    cvtps2pd xmm0, [rsi]        ; two bases, widened exactly
    cvtps2pd xmm1, [rdx]
    call    powf64__packed2  ; no GPRs used
    cvtpd2ps xmm0, xmm0         ; single rounding to float
    movq    [rdi], xmm0
    add     rsi, 8
    add     rdx, 8
    add     rdi, 8
    dec     rcx
    jnz     .loop
.tail:
    and     r10, 1
    jz      .done
.tail_loop:
    movss   xmm0, [rsi]
    movss   xmm1, [rdx]
    call    umath_pow_f32
    movss   [rdi], xmm0
    add     rsi, 4
    add     rdx, 4
    add     rdi, 4
    dec     r10
    jnz     .tail_loop
.done:
    ret

%endif ; GUARD_LIB_UMATH_MATH_FN_POW_F32_ASM
