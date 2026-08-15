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
;   - pow(0, y>0) = 0, pow(0, y<0) = +Inf (a genuine pole).
;   - pow(x<0, y): real-valued only for integer y (even -> positive result,
;     odd -> negative), NaN otherwise.
;
; Same not-attempted scope as pow_f32.asm: exact IEEE Inf-argument
; semantics fall through to exp_f64's saturate-instead-of-overflow
; behavior rather than a literal Inf.
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

section .rodata
align 16
powf64_one:        dq 1.0
powf64_nan_bits:   dq 0x7FF8000000000000
powf64_pos_inf:    dq 0x7FF0000000000000

align 16
powf64_sign_mask:  dq 0x8000000000000000, 0x8000000000000000

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

    ; x == 0, y != 0
    ucomisd xmm1, xmm2
    ja      .return_zero          ; y > 0 -> 0
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

    sub     rsp, 8
    movsd   [rsp], xmm1
    call    umath_log_f64
    movsd   xmm1, [rsp]
    add     rsp, 8
    mulsd   xmm0, xmm1
    call    umath_exp_f64         ; xmm0 = |x|^y

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
