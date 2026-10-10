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

%include "lib/umath/math_fn/sqrt_f64.asm"

section .rodata
align 16
hypotf64_pos_inf:  dq 0x7FF0000000000000
hypotf64_nan_bits: dq 0x7FF8000000000000
hypotf64_one:      dq 1.0

align 16
hypotf64_p_one:    dq 1.0, 1.0
hypotf64_p_abs:    dq 0x7FFFFFFFFFFFFFFF, 0x7FFFFFFFFFFFFFFF
hypotf64_p_inf:    dq 0x7FF0000000000000, 0x7FF0000000000000
hypotf64_p_nan:    dq 0x7FF8000000000000, 0x7FF8000000000000

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
; hypotf64_blend - lanes of %1 where mask %2 is set take %3 (register or memory)
; args:    %1 = values (in/out), %2 = mask (clobbered), %3 = source, %4 = scratch
; -----------------------------------------------------------------------------
%macro hypotf64_blend 4
    movapd  %4, %3
    andpd   %4, %2
    andnpd  %2, %1
    orpd    %2, %4
    movapd  %1, %2
%endmacro

; -----------------------------------------------------------------------------
; hypotf64__packed2 - internal: hypot of 2 lane pairs, bit-identical to
;                   umath_hypot_f64 per lane
; args:    xmm0 = x lanes, xmm1 = y lanes
; returns: xmm0 = results
; a*sqrt(1 + (b/a)^2) on every lane, then the scalar's cases, lowest
; priority first: a == 0 -> +0, NaN -> NaN, an infinite input -> +Inf.
; Clobbers xmm1-xmm8, no GPRs. Not declared global.
; -----------------------------------------------------------------------------
hypotf64__packed2:
    movapd  xmm2, xmm0
    andpd   xmm2, [rel hypotf64_p_abs]  ; |x|
    movapd  xmm3, xmm1
    andpd   xmm3, [rel hypotf64_p_abs]  ; |y|
    movapd  xmm5, xmm2
    maxpd   xmm5, xmm3          ; a
    movapd  xmm6, xmm2
    minpd   xmm6, xmm3          ; b
    movapd  xmm7, xmm6
    divpd   xmm7, xmm5          ; b/a
    mulpd   xmm7, xmm7
    addpd   xmm7, [rel hypotf64_p_one]
    sqrtpd  xmm7, xmm7
    mulpd   xmm7, xmm5          ; a * sqrt(1 + (b/a)^2)

    xorpd   xmm4, xmm4
    movapd  xmm8, xmm5
    cmpeqpd xmm8, xmm4          ; a == 0: +0
    hypotf64_blend xmm7, xmm8, xmm4, xmm6
    movapd  xmm8, xmm0
    cmpunordpd xmm8, xmm1       ; NaN x or y
    hypotf64_blend xmm7, xmm8, [rel hypotf64_p_nan], xmm6
    movapd  xmm8, xmm2
    cmpeqpd xmm8, [rel hypotf64_p_inf]
    movapd  xmm6, xmm3
    cmpeqpd xmm6, [rel hypotf64_p_inf]
    orpd    xmm8, xmm6          ; an infinite input: +Inf, even with a NaN
    hypotf64_blend xmm7, xmm8, [rel hypotf64_p_inf], xmm6
    movapd  xmm0, xmm7
    ret

; -----------------------------------------------------------------------------
; umath_hypot_f64_array - hypot(x, y) elementwise for two arrays
; args:    rdi = destination pointer (dst)
;          rsi = first operand array (xs)
;          rdx = second operand array (ys)
;          rcx = size of arrays (count)
; returns: void
;
; Groups of 2 run through hypotf64__packed2 (bit-identical to umath_hypot_f64);
; the remainder goes through the scalar routine.
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

    mov     r10, rcx            ; count; the scalar tail clobbers rcx
    shr     rcx, 1
    jz      .tail
.loop:
    movupd  xmm0, [rsi]
    movupd  xmm1, [rdx]
    call    hypotf64__packed2  ; no GPRs used
    movupd  [rdi], xmm0
    add     rsi, 16
    add     rdx, 16
    add     rdi, 16
    dec     rcx
    jnz     .loop
.tail:
    and     r10, 1
    jz      .done
.tail_loop:
    movsd   xmm0, [rsi]
    movsd   xmm1, [rdx]
    call    umath_hypot_f64
    movsd   [rdi], xmm0
    add     rsi, 8
    add     rdx, 8
    add     rdi, 8
    dec     r10
    jnz     .tail_loop
.done:
    ret

%endif ; GUARD_LIB_UMATH_MATH_FN_HYPOT_F64_ASM
