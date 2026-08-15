%ifndef GUARD_LIB_UMATH_MATH_FN_EXP_F64_ASM
%define GUARD_LIB_UMATH_MATH_FN_EXP_F64_ASM
; =============================================================================
; umath - unified math library
; math_fn/exp_f64.asm - double-precision natural exponential (e^x)
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; Algorithm: same range-reduction shape as exp_f32.asm, adjusted for double
; precision:
;
;   1. Clamp x to [MINLOG, MAXLOG] = [-1022*ln2, 1023*ln2], the exact bounds
;      that keep k (see below) inside the valid *normal* double exponent
;      range. This saturates rather than producing +Inf/0 or a subnormal
;      2^k from the bit-construction step, same rationale as the f32 path.
;   2. k = round_to_nearest(x * log2(e))
;   3. r = x - k*C1 - k*C2, ln(2) split into an exact hi/lo pair (C1 has its
;      low 32 mantissa bits zeroed, C2 is the exact residual, verified by
;      construction so C1+C2 rounds back to ln(2) with zero error) so that
;      k*C1 stays exact for |k| well beyond the ~1023 this ever sees.
;   4. exp(r) via a 13-term Horner-form Taylor series (coefficients 1/n! for
;      n=13..1). Unlike the f32 path's 5-term minimax polynomial, double
;      precision on the same |r| <= ln(2)/2 reduced range needs this many
;      terms before the next term drops below 2^-53 — a narrower reduction
;      (table of 2^(j/32)-style) would let a shorter polynomial reach the
;      same precision, but costs a lookup table this avoids.
;   5. result = p(r) * 2^k, with 2^k's IEEE-754 bits built directly: k is
;      converted to a packed 32-bit int (exact, since it's already
;      integral), sign-extended to 64-bit lanes (pmovsxdq), biased by 1023,
;      and shifted into the exponent field (bits 62..52).
;
; Design & Optimization:
;   - Scalar path (xmm0) builds 2^k via a GPR round-trip (cvttsd2si/movq).
;   - Array/inplace paths run the identical algorithm 2-wide with packed
;     double ops, unrolled to process 4 doubles (two xmm regs) per
;     iteration, with a residual tail.
; =============================================================================

bits 64

section .rodata
align 16
expf64_log2e:   dq 1.4426950408889634, 1.4426950408889634
expf64_c1:       dq 0.6931471806019545, 0.6931471806019545      ; ln(2) hi (exact, low 32 mantissa bits zeroed)
expf64_c2:       dq -4.2009173917278986e-11, -4.2009173917278986e-11 ; ln(2) lo (exact residual: C1+C2 rounds to ln(2))
expf64_p13:       dq 1.6059043836821613e-10, 1.6059043836821613e-10
expf64_p12:       dq 2.08767569878681e-09, 2.08767569878681e-09
expf64_p11:       dq 2.505210838544172e-08, 2.505210838544172e-08
expf64_p10:       dq 2.755731922398589e-07, 2.755731922398589e-07
expf64_p9:        dq 2.7557319223985893e-06, 2.7557319223985893e-06
expf64_p8:        dq 2.48015873015873e-05, 2.48015873015873e-05
expf64_p7:        dq 0.0001984126984126984, 0.0001984126984126984
expf64_p6:        dq 0.001388888888888889, 0.001388888888888889
expf64_p5:        dq 0.008333333333333333, 0.008333333333333333
expf64_p4:        dq 0.041666666666666664, 0.041666666666666664
expf64_p3:        dq 0.16666666666666666, 0.16666666666666666
expf64_p2:        dq 0.5, 0.5
expf64_one:       dq 1.0, 1.0
expf64_maxlog:    dq 709.0895657128241, 709.0895657128241
expf64_minlog:    dq -708.3964185322641, -708.3964185322641
expf64_bias_i64:      dq 1023, 1023

section .text

; -----------------------------------------------------------------------------
; umath_exp_f64 - scalar double-precision e^x
; args:    xmm0 = input value (x)
; returns: xmm0 = e^x (saturated to e^MINLOG..e^MAXLOG for extreme input)
; -----------------------------------------------------------------------------
global umath_exp_f64
umath_exp_f64:
    minsd   xmm0, [rel expf64_maxlog]
    maxsd   xmm0, [rel expf64_minlog]

    movsd   xmm1, [rel expf64_log2e]
    mulsd   xmm1, xmm0
    roundsd xmm1, xmm1, 0        ; xmm1 = k (round to nearest)

    movsd   xmm2, xmm1
    mulsd   xmm2, [rel expf64_c1]
    subsd   xmm0, xmm2
    movsd   xmm2, xmm1
    mulsd   xmm2, [rel expf64_c2]
    subsd   xmm0, xmm2           ; xmm0 = r

    movsd   xmm2, [rel expf64_p13]
    mulsd   xmm2, xmm0
    addsd   xmm2, [rel expf64_p12]
    mulsd   xmm2, xmm0
    addsd   xmm2, [rel expf64_p11]
    mulsd   xmm2, xmm0
    addsd   xmm2, [rel expf64_p10]
    mulsd   xmm2, xmm0
    addsd   xmm2, [rel expf64_p9]
    mulsd   xmm2, xmm0
    addsd   xmm2, [rel expf64_p8]
    mulsd   xmm2, xmm0
    addsd   xmm2, [rel expf64_p7]
    mulsd   xmm2, xmm0
    addsd   xmm2, [rel expf64_p6]
    mulsd   xmm2, xmm0
    addsd   xmm2, [rel expf64_p5]
    mulsd   xmm2, xmm0
    addsd   xmm2, [rel expf64_p4]
    mulsd   xmm2, xmm0
    addsd   xmm2, [rel expf64_p3]
    mulsd   xmm2, xmm0
    addsd   xmm2, [rel expf64_p2]
    mulsd   xmm2, xmm0
    addsd   xmm2, [rel expf64_one]
    mulsd   xmm2, xmm0
    addsd   xmm2, [rel expf64_one]  ; xmm2 = p(r) = 1 + r*(1 + r*(0.5 + ... ))

    cvttsd2si rax, xmm1            ; k already integral; truncate is exact
    add     rax, 1023
    shl     rax, 52
    movq    xmm4, rax              ; xmm4 = bit pattern of 2^k

    mulsd   xmm2, xmm4
    movapd  xmm0, xmm2
    ret

; -----------------------------------------------------------------------------
; umath_exp_f64__reduce2 - internal helper: packed 2-wide e^x, in place on xmm0
; Not declared global: only callable from within this translation unit.
; Clobbers xmm1-xmm4.
; -----------------------------------------------------------------------------
umath_exp_f64__reduce2:
    minpd   xmm0, [rel expf64_maxlog]
    maxpd   xmm0, [rel expf64_minlog]

    movapd  xmm1, [rel expf64_log2e]
    mulpd   xmm1, xmm0
    roundpd xmm1, xmm1, 0        ; xmm1 = k (per lane)

    movapd  xmm2, xmm1
    mulpd   xmm2, [rel expf64_c1]
    subpd   xmm0, xmm2
    movapd  xmm2, xmm1
    mulpd   xmm2, [rel expf64_c2]
    subpd   xmm0, xmm2           ; xmm0 = r

    movapd  xmm2, [rel expf64_p13]
    mulpd   xmm2, xmm0
    addpd   xmm2, [rel expf64_p12]
    mulpd   xmm2, xmm0
    addpd   xmm2, [rel expf64_p11]
    mulpd   xmm2, xmm0
    addpd   xmm2, [rel expf64_p10]
    mulpd   xmm2, xmm0
    addpd   xmm2, [rel expf64_p9]
    mulpd   xmm2, xmm0
    addpd   xmm2, [rel expf64_p8]
    mulpd   xmm2, xmm0
    addpd   xmm2, [rel expf64_p7]
    mulpd   xmm2, xmm0
    addpd   xmm2, [rel expf64_p6]
    mulpd   xmm2, xmm0
    addpd   xmm2, [rel expf64_p5]
    mulpd   xmm2, xmm0
    addpd   xmm2, [rel expf64_p4]
    mulpd   xmm2, xmm0
    addpd   xmm2, [rel expf64_p3]
    mulpd   xmm2, xmm0
    addpd   xmm2, [rel expf64_p2]
    mulpd   xmm2, xmm0
    addpd   xmm2, [rel expf64_one]
    mulpd   xmm2, xmm0
    addpd   xmm2, [rel expf64_one]  ; xmm2 = p(r) per lane

    cvttpd2dq xmm4, xmm1          ; low 64 bits = two packed int32 k values (exact)
    pmovsxdq  xmm4, xmm4          ; sign-extend to two packed int64 k values
    paddq     xmm4, [rel expf64_bias_i64]
    psllq     xmm4, 52            ; xmm4 = bit pattern of 2^k, per lane

    mulpd   xmm2, xmm4
    movapd  xmm0, xmm2
    ret

; -----------------------------------------------------------------------------
; umath_exp_f64_array - e^x for an array of doubles
; args:    rdi = destination pointer (dst)
;          rsi = source pointer (src)
;          rdx = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_exp_f64_array
umath_exp_f64_array:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done
    test    rdx, rdx
    jz      .done

    cmp     rdx, 4
    jb      .residuals

    mov     rcx, rdx
    shr     rcx, 2               ; count of 4-double (2x xmm) blocks

.loop_unrolled:
    movupd  xmm0, [rsi]
    movupd  xmm5, [rsi + 16]
    call    umath_exp_f64__reduce2
    movapd  xmm6, xmm0
    movapd  xmm0, xmm5
    call    umath_exp_f64__reduce2
    movupd  [rdi], xmm6
    movupd  [rdi + 16], xmm0

    add     rsi, 32
    add     rdi, 32
    dec     rcx
    jnz     .loop_unrolled

    and     rdx, 3
    jz      .done

.residuals:
    movsd   xmm0, [rsi]
    call    umath_exp_f64
    movsd   [rdi], xmm0
    add     rsi, 8
    add     rdi, 8
    dec     rdx
    jnz     .residuals

.done:
    ret

; -----------------------------------------------------------------------------
; umath_exp_f64_inplace - e^x in place for a double array
; args:    rdi = buffer pointer (buf)
;          rsi = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_exp_f64_inplace
umath_exp_f64_inplace:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done

    cmp     rsi, 4
    jb      .residuals

    mov     rcx, rsi
    shr     rcx, 2

.loop_unrolled:
    movupd  xmm0, [rdi]
    movupd  xmm5, [rdi + 16]
    call    umath_exp_f64__reduce2
    movapd  xmm6, xmm0
    movapd  xmm0, xmm5
    call    umath_exp_f64__reduce2
    movupd  [rdi], xmm6
    movupd  [rdi + 16], xmm0

    add     rdi, 32
    dec     rcx
    jnz     .loop_unrolled

    and     rsi, 3
    jz      .done

.residuals:
    movsd   xmm0, [rdi]
    call    umath_exp_f64
    movsd   [rdi], xmm0
    add     rdi, 8
    dec     rsi
    jnz     .residuals

.done:
    ret

%endif ; GUARD_LIB_UMATH_MATH_FN_EXP_F64_ASM
