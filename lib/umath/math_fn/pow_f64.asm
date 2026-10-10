%ifndef GUARD_LIB_UMATH_MATH_FN_POW_F64_ASM
%define GUARD_LIB_UMATH_MATH_FN_POW_F64_ASM
; =============================================================================
; umath - unified math library
; math_fn/pow_f64.asm - double-precision power function (x^y)
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; Same algorithm and special cases as pow_f32.asm (see that file for the
; full rationale): pow(x, y) = exp(y * ln(x)) for x > 0, built on
; umath_log_f64/umath_exp_f64, plus:
;
;   - pow(x, ±0) = 1 for any x, including NaN x.
;   - pow(1, y) = 1 for any y, including NaN y.
;   - NaN propagates otherwise.
;   - pow(+/-0, y>0) = +0, pow(+/-0, y<0) = +Inf (a genuine pole); an odd
;     integer y keeps the sign of x (pow(-0, 3) = -0, pow(-0, -1) = -Inf).
;   - pow(x<0, y): real-valued only for integer y (even -> positive result,
;     odd -> negative), NaN otherwise; |x| == 1 gives exactly +/-1.
;
; Same scope as pow_f32.asm: infinities fall out of exp_f64's overflow to
; +Inf / underflow to 0; pow(-Inf, non-integer y) returns NaN.
;
; Accuracy: the relative error of exp(y*ln(x)) grows with |y*ln(x)|, so
; results near the top or bottom of the double range carry up to ~1e3 ULP.
;
; Two bugs pow_f32.asm shipped with initially and had to be fixed, avoided
; here from the start:
;   - ucomisd sets ZF=1 for both "equal" and "unordered" (NaN), so a bare
;     je after it can't distinguish "y == 0" from "y is NaN" — every je
;     below is guarded by a jp check first.
;   - xorpd needs a 16-byte-aligned, full 128-bit memory operand; the sign
;     mask gets its own align 16 and all two lanes rather than a single dq.
; =============================================================================

bits 64

%include "lib/umath/math_fn/log_f64.asm"
%include "lib/umath/math_fn/exp_f64.asm"
%include "lib/umath/cpuid/fallback.asm"

section .rodata
align 16
powf64_one:        dq 1.0
powf64_nan_bits:   dq 0x7FF8000000000000
powf64_pos_inf:    dq 0x7FF0000000000000

align 16
powf64_sign_mask:  dq 0x8000000000000000, 0x8000000000000000
powf64_pos_inf_vec: dq 0x7FF0000000000000, 0x7FF0000000000000
powf64_p_abs:       dq 0x7FFFFFFFFFFFFFFF, 0x7FFFFFFFFFFFFFFF

section .text

; -----------------------------------------------------------------------------
; umath_pow_f64 - scalar double-precision x^y
; args:    xmm0 = base (x)
;          xmm1 = exponent (y)
; returns: xmm0 = x^y
; -----------------------------------------------------------------------------
global umath_pow_f64
umath_pow_f64:
    xorpd   xmm2, xmm2

    ucomisd xmm1, xmm2
    jp      .y_not_zero
    je      .return_one           ; y == 0 -> 1, for any x (including NaN)
.y_not_zero:

    movsd   xmm3, [rel powf64_one]
    ucomisd xmm0, xmm3
    jp      .x_not_one
    je      .return_one           ; x == 1 -> 1, for any y (including NaN)
.x_not_one:

    ucomisd xmm0, xmm0
    jp      .return_nan           ; x is NaN
    ucomisd xmm1, xmm1
    jp      .return_nan           ; y is NaN

    ucomisd xmm0, xmm2
    jne     .x_nonzero

    ; x == +/-0, y != 0. An odd integer y keeps the sign of x:
    ; pow(-0, 3) = -0 and pow(-0, -1) = -Inf; otherwise +0 / +Inf.
    um_roundsd xmm4, xmm1, 0
    ucomisd xmm4, xmm1
    jne     .zero_even            ; non-integer y (incl. +/-Inf) acts as even
    cvttsd2si rax, xmm4           ; huge |y| converts to 0x80..0 = even, which they are
    test    eax, 1
    jz      .zero_even
    ucomisd xmm1, xmm2
    ja      .done                 ; odd y > 0: x itself (+/-0)
    andpd   xmm0, [rel powf64_sign_mask]
    orpd    xmm0, [rel powf64_pos_inf_vec]
    ret                           ; odd y < 0: +/-Inf with the sign of x
.zero_even:
    ucomisd xmm1, xmm2
    ja      .return_zero          ; y > 0 -> +0
    movsd   xmm0, [rel powf64_pos_inf]
    ret                           ; y < 0 -> +Inf (genuine pole)

.x_nonzero:
    ucomisd xmm0, xmm2
    jae     .x_positive           ; x > 0 (x == 0 already handled above)

    ; x < 0: only defined for integer y
    um_roundsd xmm4, xmm1, 0
    ucomisd xmm4, xmm1
    jne     .return_nan           ; y is not an integer

    cvttsd2si rax, xmm4           ; exact: xmm4 already holds an integral value
    and     eax, 1
    push    rax                   ; spill parity across the calls below

    xorpd   xmm0, [rel powf64_sign_mask]  ; xmm0 = |x| (x < 0 here)

    ; |x| == 1: |x|^y is exactly 1 for every integer y, including +/-Inf
    ; (where exp(y * ln|x|) would be exp(Inf * 0) = NaN)
    ucomisd xmm0, [rel powf64_one]
    je      .apply_sign

    sub     rsp, 16               ; 16 (not 8) keeps rsp aligned at the calls
    movsd   [rsp], xmm1
    call    umath_log_f64
    movsd   xmm1, [rsp]
    add     rsp, 16
    mulsd   xmm0, xmm1
    call    umath_exp_f64         ; xmm0 = |x|^y

.apply_sign:
    pop     rax
    test    eax, eax
    jz      .done
    xorpd   xmm0, [rel powf64_sign_mask]  ; odd y: negate
.done:
    ret

.x_positive:
    sub     rsp, 8
    movsd   [rsp], xmm1
    call    umath_log_f64
    movsd   xmm1, [rsp]
    add     rsp, 8
    mulsd   xmm0, xmm1
    call    umath_exp_f64
    ret

.return_one:
    movsd   xmm0, [rel powf64_one]
    ret

.return_zero:
    xorpd   xmm0, xmm0
    ret

.return_nan:
    mov     rax, [rel powf64_nan_bits]
    movq    xmm0, rax
    ret

; -----------------------------------------------------------------------------
; powf64__packed2 - internal: x^y of two lane pairs, bit-identical to
;                  umath_pow_f64 per lane
; args:    xmm0 = two bases, xmm1 = two exponents
; returns: xmm0 = two results
;
; Every lane computes exp(y * ln|x|) with the packed log and exp cores (each
; bit-identical to its scalar routine), negated for a negative base with an
; odd integer exponent. The scalar routine's special cases are then applied
; as lane masks, lowest priority first, so the case the scalar tests first
; wins: y == 0 -> 1, x == 1 -> 1, NaN -> NaN, x == +/-0 (signed by the
; parity of y), x < 0 with non-integer y -> NaN, x < 0 with |x| == 1 -> +/-1.
; Integer and odd tests are exact (roundpd): an infinite or huge y counts as
; even, as the scalar's cvttsd2si (0x8000...) does.
; Clobbers xmm1-xmm15, no GPRs. Not declared global.
; -----------------------------------------------------------------------------
powf64__packed2:
    movapd  xmm10, xmm0          ; x
    movapd  xmm11, xmm1          ; y
    andpd   xmm0, [rel powf64_p_abs]
    call    logf64__packed2      ; ln|x| (xmm1-xmm9)
    mulpd   xmm0, xmm11          ; y * ln|x|
    call    umath_exp_f64__reduce2   ; |x|^y (xmm1-xmm4)
    movapd  xmm12, xmm0

    ; y integral (yi == y) and odd (yi - 2*floor(yi/2) == 1)
    movapd  xmm13, xmm11
    um_roundpd xmm13, xmm13, 0      ; yi
    movapd  xmm14, xmm13
    cmpeqpd xmm14, xmm11         ; integral y
    movapd  xmm1, xmm13
    mulpd   xmm1, [rel logf64_p_half]
    um_roundpd xmm1, xmm1, 1
    addpd   xmm1, xmm1           ; 2 * floor(yi / 2), exact
    movapd  xmm15, xmm13
    subpd   xmm15, xmm1
    cmpeqpd xmm15, [rel logf64_p_one]
    andpd   xmm15, xmm14         ; odd integer y

    xorpd   xmm2, xmm2           ; 0.0 (kept to the end)
    movapd  xmm3, xmm10
    cmpltpd xmm3, xmm2           ; x < 0

    ; x < 0, odd integer y: negate
    movapd  xmm4, xmm3
    andpd   xmm4, xmm15
    andpd   xmm4, [rel powf64_sign_mask]
    xorpd   xmm12, xmm4

    ; x < 0, y not integral: NaN
    movapd  xmm4, xmm14
    andnpd  xmm4, xmm3
    logf64_blend xmm12, xmm4, [rel logf64_p_nan], xmm5

    ; x < 0, |x| == 1, integral y: exactly +/-1
    movapd  xmm4, xmm10
    andpd   xmm4, [rel powf64_p_abs]
    cmpeqpd xmm4, [rel logf64_p_one]
    andpd   xmm4, xmm3
    andpd   xmm4, xmm14
    movapd  xmm6, xmm15
    andpd   xmm6, [rel powf64_sign_mask]
    orpd    xmm6, [rel logf64_p_one]
    logf64_blend xmm12, xmm4, xmm6, xmm5

    ; x == +/-0: odd integer y keeps the sign of x
    movapd  xmm6, xmm10
    andpd   xmm6, [rel powf64_sign_mask]
    orpd    xmm6, [rel powf64_pos_inf_vec] ; +/-Inf, sign of x
    movapd  xmm7, xmm2
    cmpltpd xmm7, xmm11          ; y > 0
    movapd  xmm8, xmm7
    logf64_blend xmm6, xmm8, xmm10, xmm5   ; odd y: y > 0 ? x : +/-Inf
    movapd  xmm9, [rel powf64_pos_inf_vec]
    movapd  xmm8, xmm7
    logf64_blend xmm9, xmm8, xmm2, xmm5    ; even y: y > 0 ? +0 : +Inf
    movapd  xmm8, xmm15
    logf64_blend xmm9, xmm8, xmm6, xmm5
    movapd  xmm4, xmm10
    cmpeqpd xmm4, xmm2
    logf64_blend xmm12, xmm4, xmm9, xmm5

    ; NaN x or y
    movapd  xmm4, xmm10
    cmpunordpd xmm4, xmm11
    logf64_blend xmm12, xmm4, [rel logf64_p_nan], xmm5
    ; x == 1, then y == +/-0 (the scalar's first two tests)
    movapd  xmm4, xmm10
    cmpeqpd xmm4, [rel logf64_p_one]
    logf64_blend xmm12, xmm4, [rel logf64_p_one], xmm5
    movapd  xmm4, xmm11
    cmpeqpd xmm4, xmm2
    logf64_blend xmm12, xmm4, [rel logf64_p_one], xmm5

    movapd  xmm0, xmm12
    ret

; -----------------------------------------------------------------------------
; umath_pow_f64_array - pow(x, y) elementwise for two arrays
; args:    rdi = destination pointer (dst)
;          rsi = first operand array (xs)
;          rdx = second operand array (ys)
;          rcx = size of arrays (count)
; returns: void
;
; Pairs run through powf64__packed2 (bit-identical to umath_pow_f64); an odd
; last element goes through the scalar routine.
; -----------------------------------------------------------------------------
global umath_pow_f64_array
umath_pow_f64_array:
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
    call    powf64__packed2  ; no GPRs used
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
    call    umath_pow_f64
    movsd   [rdi], xmm0
    add     rsi, 8
    add     rdx, 8
    add     rdi, 8
    dec     r10
    jnz     .tail_loop
.done:
    ret

%endif ; GUARD_LIB_UMATH_MATH_FN_POW_F64_ASM
