%ifndef GUARD_LIB_UMATH_MATH_FN_HYPOT_F64_ASM
%define GUARD_LIB_UMATH_MATH_FN_HYPOT_F64_ASM
; =============================================================================
; umath - unified math library
; math_fn/hypot_f64.asm - double-precision Euclidean distance sqrt(x^2+y^2)
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; Same overflow/underflow-safe algorithm as hypot_f32.asm: scale by
; a = max(|x|,|y|), b = min(|x|,|y|), hypot = a * sqrt(1 + (b/a)^2). See
; that file for the full rationale. Uses the already-verified
; umath_sqrt_f64 for the final step.
;
; IEEE 754 special cases (checked in this order):
;   hypot(x, y) = +Inf if either |x| or |y| is +Inf, even if the other is
;                 NaN (Inf takes priority over NaN)
;   hypot(x, y) = NaN  if either is NaN and neither is Inf
; =============================================================================

bits 64

section .rodata
align 16
hypotf64_pos_inf:  dq 0x7FF0000000000000
hypotf64_nan_bits: dq 0x7FF8000000000000
hypotf64_one:      dq 1.0

section .text

; -----------------------------------------------------------------------------
; umath_hypot_f64 - scalar double-precision sqrt(x^2 + y^2)
; args:    xmm0 = x
;          xmm1 = y
; returns: xmm0 = hypot(x, y)
; -----------------------------------------------------------------------------
global umath_hypot_f64
umath_hypot_f64:
    movq    rax, xmm0
    mov     r8, 0x7FFFFFFFFFFFFFFF
    and     rax, r8
    movq    xmm2, rax              ; xmm2 = |x|
    movq    rax, xmm1
    and     rax, r8
    movq    xmm3, rax              ; xmm3 = |y|

    ; See hypot_f32.asm's comment at the equivalent check: ucomisd sets
    ; ZF=1 for both "equal" and "unordered" (NaN), so jp must guard je
    ; here or hypot(NaN, finite) wrongly returns +Inf.
    movsd   xmm4, [rel hypotf64_pos_inf]
    ucomisd xmm2, xmm4
    jp      .ax_not_inf
    je      .return_pos_inf
.ax_not_inf:
    ucomisd xmm3, xmm4
    jp      .ay_not_inf
    je      .return_pos_inf
.ay_not_inf:

    ucomisd xmm0, xmm0
    jp      .return_nan
    ucomisd xmm1, xmm1
    jp      .return_nan

    ; a = max(|x|,|y|), b = min(|x|,|y|)
    movsd   xmm5, xmm2
    maxsd   xmm5, xmm3              ; xmm5 = a
    movsd   xmm6, xmm2
    minsd   xmm6, xmm3              ; xmm6 = b

    xorpd   xmm0, xmm0
    ucomisd xmm5, xmm0
    je      .done                   ; a == 0 -> both are 0, hypot is 0

    divsd   xmm6, xmm5               ; xmm6 = b/a, in [0,1]
    mulsd   xmm6, xmm6                ; xmm6 = (b/a)^2
    addsd   xmm6, [rel hypotf64_one]  ; xmm6 = 1 + (b/a)^2

    movsd   xmm0, xmm6
    call    umath_sqrt_f64
    mulsd   xmm0, xmm5                ; xmm0 = a * sqrt(1 + (b/a)^2)
.done:
    ret

.return_pos_inf:
    movsd   xmm0, [rel hypotf64_pos_inf]
    ret

.return_nan:
    mov     rax, [rel hypotf64_nan_bits]
    movq    xmm0, rax
    ret

; -----------------------------------------------------------------------------
; umath_hypot_f64_array - hypot(x,y) elementwise for two arrays of doubles
; args:    rdi = destination pointer (dst)
;          rsi = x array pointer (xs)
;          rdx = y array pointer (ys)
;          rcx = size of arrays (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_hypot_f64_array
umath_hypot_f64_array:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done
    test    rdx, rdx
    jz      .done
    test    rcx, rcx
    jz      .done

.loop:
    movsd   xmm0, [rsi]
    movsd   xmm1, [rdx]
    call    umath_hypot_f64
    movsd   [rdi], xmm0
    add     rsi, 8
    add     rdx, 8
    add     rdi, 8
    dec     rcx
    jnz     .loop

.done:
    ret

%endif ; GUARD_LIB_UMATH_MATH_FN_HYPOT_F64_ASM
