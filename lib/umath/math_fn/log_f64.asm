%ifndef GUARD_LIB_UMATH_MATH_FN_LOG_F64_ASM
%define GUARD_LIB_UMATH_MATH_FN_LOG_F64_ASM
; =============================================================================
; umath - unified math library
; math_fn/log_f64.asm - double-precision natural logarithm (ln x)
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; Same atanh-series algorithm as log_f32.asm (see that file for the full
; derivation), widened to double precision:
;
;   1. x = m * 2^k via the IEEE-754 bit pattern (11-bit exponent, bias 1023).
;   2. If m > sqrt(2), halve m and increment k -> m in [sqrt(2)/2, sqrt(2)).
;   3. f = m - 1 (exact), s = f/(2+f) in [-0.1716, 0.1716], z = s^2, and
;      ln(m) = f - (f^2/2 - s*(f^2/2 + R(z))),
;      R(z) = 2z/3 + 2z^2/5 + ... + 2z^11/23 (11 terms; the next one drops
;      below 2^-56 of the result on this range). This is the same atanh
;      series, 2*atanh(s), regrouped so that the large term f carries no
;      rounding at all and only the small corrections round.
;   4. result = k*ln2_hi - ((f^2/2 - (s*(f^2/2 + R) + k*ln2_lo)) - f), with
;      ln(2) split so that k*ln2_hi is exact for every exponent. This
;      takes the worst case from ~3 ULP (2*s*(1 + s^2/3 + ...) + k*ln2,
;      where the rounded division and the rounded k*ln2 both reach the
;      result) to about 1 ULP.
;
; Same domain behavior as log_f32.asm (-Inf at 0, NaN below 0 or on NaN
; input). The array/inplace paths run the same algorithm two lanes at a
; time (logf64__packed2): identical operations in identical order per lane,
; the scalar's integer exponent adjustments done as exact double additions,
; and the domain cases blended in at the end with the scalar's constants,
; so every element is bit-for-bit what umath_log_f64 returns.
; =============================================================================

bits 64

section .rodata
align 16
logf64_one:       dq 1.0
logf64_half:      dq 0.5
logf64_sqrt2:     dq 1.4142135623730951
logf64_two:        dq 2.0
logf64_ln2_hi:     dq 0x3FE62E42FEE00000      ; ln(2), 32 bits: k*hi exact
logf64_ln2_lo:     dq 0x3DEA39EF35793C76      ; ln(2) - hi
logf64_c1:          dq 0.6666666666666666
logf64_c2:          dq 0.4
logf64_c3:          dq 0.2857142857142857
logf64_c4:          dq 0.2222222222222222
logf64_c5:          dq 0.18181818181818182
logf64_c6:          dq 0.15384615384615385
logf64_c7:          dq 0.13333333333333333
logf64_c8:          dq 0.11764705882352941
logf64_c9:          dq 0.10526315789473684
logf64_c10:         dq 0.09523809523809523
logf64_c11:         dq 0.08695652173913043
logf64_nan_bits:    dq 0x7FF8000000000000
logf64_neg_inf_bits: dq 0xFFF0000000000000
logf64_dbl_min:     dq 2.2250738585072014e-308   ; smallest normal double
logf64_two_pow_54:  dq 18014398509481984.0        ; 2^54, exact power-of-two scale
logf64_pos_inf:     dq 0x7FF0000000000000

; two-lane copies for logf64__packed2 (16-byte aligned memory operands)
align 16
logf64_p_one:       dq 1.0, 1.0
logf64_p_half:      dq 0.5, 0.5
logf64_p_sqrt2:     dq 1.4142135623730951, 1.4142135623730951
logf64_p_two:      dq 2.0, 2.0
logf64_p_ln2_hi:   dq 0x3FE62E42FEE00000, 0x3FE62E42FEE00000
logf64_p_ln2_lo:   dq 0x3DEA39EF35793C76, 0x3DEA39EF35793C76
logf64_p_c1:        dq 0.6666666666666666, 0.6666666666666666
logf64_p_c2:        dq 0.4, 0.4
logf64_p_c3:        dq 0.2857142857142857, 0.2857142857142857
logf64_p_c4:        dq 0.2222222222222222, 0.2222222222222222
logf64_p_c5:        dq 0.18181818181818182, 0.18181818181818182
logf64_p_c6:        dq 0.15384615384615385, 0.15384615384615385
logf64_p_c7:        dq 0.13333333333333333, 0.13333333333333333
logf64_p_c8:        dq 0.11764705882352941, 0.11764705882352941
logf64_p_c9:        dq 0.10526315789473684, 0.10526315789473684
logf64_p_c10:       dq 0.09523809523809523, 0.09523809523809523
logf64_p_c11:       dq 0.08695652173913043, 0.08695652173913043
logf64_p_dbl_min:   dq 2.2250738585072014e-308, 2.2250738585072014e-308
logf64_p_two_pow_54: dq 18014398509481984.0, 18014398509481984.0
logf64_p_54:        dq 54.0, 54.0
logf64_p_mant_mask: dq 0x000FFFFFFFFFFFFF, 0x000FFFFFFFFFFFFF
logf64_p_exp_mask:  dq 0x7FF, 0x7FF
logf64_p_bias:      dq 1023, 1023
logf64_p_nan:       dq 0x7FF8000000000000, 0x7FF8000000000000
logf64_p_neg_inf:   dq 0xFFF0000000000000, 0xFFF0000000000000
logf64_p_pos_inf:   dq 0x7FF0000000000000, 0x7FF0000000000000

section .text

; -----------------------------------------------------------------------------
; umath_log_f64 - scalar double-precision natural logarithm
; args:    xmm0 = input value (val)
; returns: xmm0 = ln(val); -Inf for 0, NaN for negative input or NaN input
; -----------------------------------------------------------------------------
global umath_log_f64
umath_log_f64:
    xorpd   xmm5, xmm5
    ucomisd xmm0, xmm5
    jp      .return_nan
    ja      .positive

    je      .return_neg_inf
.return_nan:
    mov     rax, [rel logf64_nan_bits]
    movq    xmm0, rax
    ret

.return_neg_inf:
    mov     rax, [rel logf64_neg_inf_bits]
    movq    xmm0, rax
    ret

.return_pos_inf:
    movsd   xmm0, [rel logf64_pos_inf]
    ret

.positive:
    ; +Inf has an all-1s exponent field, which the bit-extraction below
    ; would otherwise silently read as an ordinary (very large) finite
    ; exponent and return a wrong finite answer for.
    ucomisd xmm0, [rel logf64_pos_inf]
    je      .return_pos_inf

    ; Subnormal input (below the smallest normal double) has an all-zero
    ; exponent field, which breaks the implicit-leading-1 assumption the
    ; bit extraction below relies on. Scale it into the normal range by an
    ; exact power of two first, and correct k for that scale afterward.
    xor     r9, r9
    movsd   xmm7, [rel logf64_dbl_min]
    comisd  xmm0, xmm7
    jae     .extract
    mulsd   xmm0, [rel logf64_two_pow_54]
    mov     r9, 54
.extract:
    movq    rax, xmm0            ; raw IEEE-754 bits (now guaranteed normal)
    mov     rcx, rax
    shr     rcx, 52
    and     rcx, 0x7FF
    sub     rcx, 1023            ; rcx = k (unbiased exponent)
    sub     rcx, r9              ; undo the subnormal pre-scale, if any

    mov     r8, 0x000FFFFFFFFFFFFF
    and     rax, r8
    mov     r8, 1023
    shl     r8, 52
    or      rax, r8
    movq    xmm1, rax            ; xmm1 = m, in [1, 2)

    movsd   xmm2, [rel logf64_sqrt2]
    comisd  xmm1, xmm2
    jbe     .no_adjust
    mulsd   xmm1, [rel logf64_half]
    inc     rcx
.no_adjust:
    cvtsi2sd xmm3, rcx           ; xmm3 = (double)k

    movsd   xmm4, xmm1
    subsd   xmm4, [rel logf64_one]  ; f = m - 1, exact
    movsd   xmm5, xmm4
    mulsd   xmm5, xmm4
    mulsd   xmm5, [rel logf64_half] ; hfsq = f^2/2
    movsd   xmm6, [rel logf64_two]
    addsd   xmm6, xmm4
    movsd   xmm7, xmm4
    divsd   xmm7, xmm6          ; s = f/(2+f)
    movsd   xmm2, xmm7
    mulsd   xmm2, xmm7          ; z = s^2

    movsd   xmm6, [rel logf64_c11]
    mulsd   xmm6, xmm2
    addsd   xmm6, [rel logf64_c10]
    mulsd   xmm6, xmm2
    addsd   xmm6, [rel logf64_c9]
    mulsd   xmm6, xmm2
    addsd   xmm6, [rel logf64_c8]
    mulsd   xmm6, xmm2
    addsd   xmm6, [rel logf64_c7]
    mulsd   xmm6, xmm2
    addsd   xmm6, [rel logf64_c6]
    mulsd   xmm6, xmm2
    addsd   xmm6, [rel logf64_c5]
    mulsd   xmm6, xmm2
    addsd   xmm6, [rel logf64_c4]
    mulsd   xmm6, xmm2
    addsd   xmm6, [rel logf64_c3]
    mulsd   xmm6, xmm2
    addsd   xmm6, [rel logf64_c2]
    mulsd   xmm6, xmm2
    addsd   xmm6, [rel logf64_c1]
    mulsd   xmm6, xmm2          ; R(z)

    addsd   xmm6, xmm5          ; hfsq + R
    mulsd   xmm6, xmm7          ; s*(hfsq + R)
    movsd   xmm2, xmm3
    mulsd   xmm2, [rel logf64_ln2_lo]
    addsd   xmm6, xmm2          ; + k*ln2_lo
    subsd   xmm5, xmm6
    subsd   xmm5, xmm4          ; (hfsq - (..)) - f
    mulsd   xmm3, [rel logf64_ln2_hi]  ; exact
    subsd   xmm3, xmm5
    movapd  xmm0, xmm3
    ret

; -----------------------------------------------------------------------------
; logf64_blend - lanes of %1 where mask %2 is set take constant %3
; args:    %1 = values (in/out), %2 = mask (clobbered), %3 = 16-byte constant
;          %4 = scratch register
; -----------------------------------------------------------------------------
%macro logf64_blend 4
    movapd  %4, %3
    andpd   %4, %2              ; constant where the mask is set
    andnpd  %2, %1              ; value where it is not
    orpd    %2, %4
    movapd  %1, %2
%endmacro

; -----------------------------------------------------------------------------
; logf64__packed2 - internal: ln(x) of two doubles, bit-identical to
;                   umath_log_f64 per lane
; args:    xmm0 = two input values
; returns: xmm0 = two results
; Clobbers xmm1-xmm9; no general-purpose registers. Not declared global.
; -----------------------------------------------------------------------------
logf64__packed2:
    movapd  xmm8, xmm0          ; original x, for the domain cases at the end

    ; subnormal lanes: x *= 2^54 and k -= 54 (the scalar's pre-scale)
    movapd  xmm1, xmm0
    cmpltpd xmm1, [rel logf64_p_dbl_min]
    movapd  xmm9, xmm1
    andpd   xmm9, [rel logf64_p_54] ; per-lane exponent correction
    movapd  xmm2, xmm0
    mulpd   xmm2, [rel logf64_p_two_pow_54]
    andpd   xmm2, xmm1
    andnpd  xmm1, xmm0
    orpd    xmm1, xmm2          ; xmm1 = x, pre-scaled where subnormal

    ; k = biased exponent - 1023 (exact as double), minus the pre-scale
    movapd  xmm3, xmm1
    psrlq   xmm3, 52
    pand    xmm3, [rel logf64_p_exp_mask]
    psubq   xmm3, [rel logf64_p_bias]
    pshufd  xmm3, xmm3, 0x08    ; the two low dwords (|k| < 2^31)
    cvtdq2pd xmm3, xmm3
    subpd   xmm3, xmm9

    ; m = mantissa with exponent forced to 0, in [1, 2)
    movapd  xmm4, xmm1
    andpd   xmm4, [rel logf64_p_mant_mask]
    orpd    xmm4, [rel logf64_p_one]

    ; m > sqrt(2): m *= 0.5 and k += 1
    movapd  xmm5, [rel logf64_p_sqrt2]
    cmpltpd xmm5, xmm4          ; mask: sqrt(2) < m
    movapd  xmm6, xmm5
    andpd   xmm6, [rel logf64_p_one]
    addpd   xmm3, xmm6
    movapd  xmm6, xmm4
    mulpd   xmm6, [rel logf64_p_half]
    andpd   xmm6, xmm5
    andnpd  xmm5, xmm4
    orpd    xmm5, xmm6          ; xmm5 = m

    movapd  xmm4, xmm5
    subpd   xmm4, [rel logf64_p_one]  ; f = m - 1
    movapd  xmm1, xmm4
    mulpd   xmm1, xmm4
    mulpd   xmm1, [rel logf64_p_half] ; hfsq
    movapd  xmm6, [rel logf64_p_two]
    addpd   xmm6, xmm4
    movapd  xmm7, xmm4
    divpd   xmm7, xmm6          ; s
    movapd  xmm2, xmm7
    mulpd   xmm2, xmm7          ; z

    movapd  xmm6, [rel logf64_p_c11]
    mulpd   xmm6, xmm2
    addpd   xmm6, [rel logf64_p_c10]
    mulpd   xmm6, xmm2
    addpd   xmm6, [rel logf64_p_c9]
    mulpd   xmm6, xmm2
    addpd   xmm6, [rel logf64_p_c8]
    mulpd   xmm6, xmm2
    addpd   xmm6, [rel logf64_p_c7]
    mulpd   xmm6, xmm2
    addpd   xmm6, [rel logf64_p_c6]
    mulpd   xmm6, xmm2
    addpd   xmm6, [rel logf64_p_c5]
    mulpd   xmm6, xmm2
    addpd   xmm6, [rel logf64_p_c4]
    mulpd   xmm6, xmm2
    addpd   xmm6, [rel logf64_p_c3]
    mulpd   xmm6, xmm2
    addpd   xmm6, [rel logf64_p_c2]
    mulpd   xmm6, xmm2
    addpd   xmm6, [rel logf64_p_c1]
    mulpd   xmm6, xmm2          ; R(z)

    addpd   xmm6, xmm1
    mulpd   xmm6, xmm7          ; s*(hfsq + R)
    movapd  xmm9, xmm3
    mulpd   xmm9, [rel logf64_p_ln2_lo]
    addpd   xmm6, xmm9
    subpd   xmm1, xmm6
    subpd   xmm1, xmm4
    mulpd   xmm3, [rel logf64_p_ln2_hi]
    subpd   xmm3, xmm1
    movapd  xmm6, xmm3          ; ln(x)

    ; domain cases, with the scalar routine's constants
    movapd  xmm1, xmm8
    cmpunordpd xmm1, xmm8       ; NaN
    xorpd   xmm2, xmm2
    movapd  xmm7, xmm8
    cmpltpd xmm7, xmm2          ; x < 0
    orpd    xmm1, xmm7
    logf64_blend xmm6, xmm1, [rel logf64_p_nan], xmm7
    movapd  xmm1, xmm8
    cmpeqpd xmm1, xmm2          ; +/-0
    logf64_blend xmm6, xmm1, [rel logf64_p_neg_inf], xmm7
    movapd  xmm1, xmm8
    cmpeqpd xmm1, [rel logf64_p_pos_inf]
    logf64_blend xmm6, xmm1, [rel logf64_p_pos_inf], xmm7

    movapd  xmm0, xmm6
    ret

; -----------------------------------------------------------------------------
; umath_log_f64_array - ln(x) for an array of doubles
; args:    rdi = destination pointer (dst)
;          rsi = source pointer (src)
;          rdx = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_log_f64_array
umath_log_f64_array:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done
    test    rdx, rdx
    jz      .done

    mov     rcx, rdx
    shr     rcx, 1              ; count of 2-double pairs
    jz      .tail
.loop2:
    movupd  xmm0, [rsi]
    call    logf64__packed2     ; preserves rcx (no GPRs used)
    movupd  [rdi], xmm0
    add     rsi, 16
    add     rdi, 16
    dec     rcx
    jnz     .loop2
.tail:
    test    rdx, 1
    jz      .done
    movsd   xmm0, [rsi]
    call    umath_log_f64
    movsd   [rdi], xmm0
.done:
    ret

; -----------------------------------------------------------------------------
; umath_log_f64_inplace - ln(x) in place for a double array
; args:    rdi = buffer pointer (buf)
;          rsi = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_log_f64_inplace
umath_log_f64_inplace:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done

    mov     rcx, rsi
    shr     rcx, 1
    jz      .tail
.loop2:
    movupd  xmm0, [rdi]
    call    logf64__packed2
    movupd  [rdi], xmm0
    add     rdi, 16
    dec     rcx
    jnz     .loop2
.tail:
    test    rsi, 1
    jz      .done
    movsd   xmm0, [rdi]
    call    umath_log_f64
    movsd   [rdi], xmm0
.done:
    ret

%endif ; GUARD_LIB_UMATH_MATH_FN_LOG_F64_ASM
