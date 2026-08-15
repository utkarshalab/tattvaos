%ifndef GUARD_LIB_UMATH_MATH_FN_HYPOT_F32_ASM
%define GUARD_LIB_UMATH_MATH_FN_HYPOT_F32_ASM
; =============================================================================
; umath - unified math library
; math_fn/hypot_f32.asm - single-precision Euclidean distance sqrt(x^2+y^2)
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; Naive sqrt(x*x + y*y) overflows for |x| or |y| individually large enough
; that squaring alone overflows to Inf (even when the true hypot result
; would fit comfortably in range), and underflows to a less precise result
; for very small inputs. The standard fix, used here:
;
;   a = max(|x|, |y|), b = min(|x|, |y|)
;   hypot = a * sqrt(1 + (b/a)^2)
;
; b/a is always in [0, 1], so the squaring that follows never overflows
; regardless of x/y's own magnitude, and only the already-verified
; umath_sqrt_f32 is needed for the final step.
;
; IEEE 754 special cases (checked in this order, matching the standard):
;   hypot(x, y) = +Inf if either |x| or |y| is +Inf, even if the other is
;                 NaN (Inf takes priority over NaN here)
;   hypot(x, y) = NaN  if either is NaN and neither is Inf
; =============================================================================

bits 64

section .rodata
align 16
hypotf32_pos_inf:  dd 0x7F800000
hypotf32_nan_bits: dd 0x7FC00000
hypotf32_one:      dd 1.0

section .text

; -----------------------------------------------------------------------------
; umath_hypot_f32 - scalar single-precision sqrt(x^2 + y^2)
; args:    xmm0 = x
;          xmm1 = y
; returns: xmm0 = hypot(x, y)
; -----------------------------------------------------------------------------
global umath_hypot_f32
umath_hypot_f32:
    movd    eax, xmm0
    and     eax, 0x7FFFFFFF
    movd    xmm2, eax              ; xmm2 = |x|
    movd    eax, xmm1
    and     eax, 0x7FFFFFFF
    movd    xmm3, eax              ; xmm3 = |y|

    ; ucomiss sets ZF=1 for both "equal" and "unordered" (NaN), so a bare
    ; je here can't tell "ax == +Inf" from "ax is NaN" — the same mistake
    ; already fixed once in pow_f32.asm, made again here and caught by
    ; testing hypot(NaN, 1.0): the buggy version returned +Inf instead of
    ; NaN, because |NaN| compared against +Inf is unordered, not equal.
    movss   xmm4, [rel hypotf32_pos_inf]
    ucomiss xmm2, xmm4
    jp      .ax_not_inf
    je      .return_pos_inf
.ax_not_inf:
    ucomiss xmm3, xmm4
    jp      .ay_not_inf
    je      .return_pos_inf
.ay_not_inf:

    ucomiss xmm0, xmm0
    jp      .return_nan
    ucomiss xmm1, xmm1
    jp      .return_nan

    ; a = max(|x|,|y|), b = min(|x|,|y|)
    movss   xmm5, xmm2
    maxss   xmm5, xmm3              ; xmm5 = a
    movss   xmm6, xmm2
    minss   xmm6, xmm3              ; xmm6 = b

    xorps   xmm0, xmm0
    ucomiss xmm5, xmm0
    je      .done                   ; a == 0 -> both are 0, hypot is 0

    divss   xmm6, xmm5               ; xmm6 = b/a, in [0,1]
    mulss   xmm6, xmm6                ; xmm6 = (b/a)^2
    addss   xmm6, [rel hypotf32_one]  ; xmm6 = 1 + (b/a)^2

    movss   xmm0, xmm6
    call    umath_sqrt_f32
    mulss   xmm0, xmm5                ; xmm0 = a * sqrt(1 + (b/a)^2)
.done:
    ret

.return_pos_inf:
    movss   xmm0, [rel hypotf32_pos_inf]
    ret

.return_nan:
    mov     eax, [rel hypotf32_nan_bits]
    movd    xmm0, eax
    ret

; -----------------------------------------------------------------------------
; umath_hypot_f32_array - hypot(x,y) elementwise for two arrays of floats
; args:    rdi = destination pointer (dst)
;          rsi = x array pointer (xs)
;          rdx = y array pointer (ys)
;          rcx = size of arrays (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_hypot_f32_array
umath_hypot_f32_array:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done
    test    rdx, rdx
    jz      .done
    test    rcx, rcx
    jz      .done

.loop:
    movss   xmm0, [rsi]
    movss   xmm1, [rdx]
    call    umath_hypot_f32
    movss   [rdi], xmm0
    add     rsi, 4
    add     rdx, 4
    add     rdi, 4
    dec     rcx
    jnz     .loop

.done:
    ret

%endif ; GUARD_LIB_UMATH_MATH_FN_HYPOT_F32_ASM
