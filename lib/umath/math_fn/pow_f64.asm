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

section .rodata
align 16
powf64_one:        dq 1.0
powf64_nan_bits:   dq 0x7FF8000000000000
powf64_pos_inf:    dq 0x7FF0000000000000

align 16
powf64_sign_mask:  dq 0x8000000000000000, 0x8000000000000000
powf64_pos_inf_vec: dq 0x7FF0000000000000, 0x7FF0000000000000

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
    roundsd xmm4, xmm1, 0
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
    roundsd xmm4, xmm1, 0
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
; umath_pow_f64_array - x^y elementwise for two arrays of doubles
; args:    rdi = destination pointer (dst)
;          rsi = base array pointer (xs)
;          rdx = exponent array pointer (ys)
;          rcx = size of arrays (count)
; returns: void
;
; count is moved out of rcx into r10 immediately: umath_log_f64 (reached
; through umath_pow_f64) clobbers rcx internally, which would otherwise
; corrupt the loop counter on the very first iteration.
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

    mov     r10, rcx

.loop:
    movsd   xmm0, [rsi]
    movsd   xmm1, [rdx]
    call    umath_pow_f64
    movsd   [rdi], xmm0
    add     rsi, 8
    add     rdx, 8
    add     rdi, 8
    dec     r10
    jnz     .loop

.done:
    ret

%endif ; GUARD_LIB_UMATH_MATH_FN_POW_F64_ASM
