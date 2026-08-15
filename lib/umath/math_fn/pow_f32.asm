%ifndef GUARD_LIB_UMATH_MATH_FN_POW_F32_ASM
%define GUARD_LIB_UMATH_MATH_FN_POW_F32_ASM
; =============================================================================
; umath - unified math library
; math_fn/pow_f32.asm - single-precision power function (x^y)
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; Algorithm: pow(x, y) = exp(y * ln(x)) for x > 0, built directly on the
; already-verified umath_log_f32/umath_exp_f32 in this same directory,
; plus the special cases IEEE 754 defines and a negative-base path:
;
;   - pow(x, ±0) = 1 for any x, including NaN x.
;   - pow(1, y) = 1 for any y, including NaN y.
;   - NaN propagates otherwise.
;   - pow(0, y>0) = 0, pow(0, y<0) = +Inf (a genuine pole, so this returns
;     true +Inf bits rather than the saturated-large-finite behavior
;     exp_f32.asm uses for smooth overflow).
;   - pow(x<0, y) is only real-valued when y is an integer: even y gives a
;     positive result, odd y gives a negative one, non-integer y is NaN.
;     |x|^y is computed via the same exp(y*ln|x|)) as the positive path.
;
; Not attempted: exact IEEE semantics for Inf-valued x or y (e.g.
; pow(Inf, 0.5)). Those fall through to exp(y*ln(x)), which inherits
; exp_f32's documented saturate-instead-of-overflow behavior rather than
; producing a literal Inf — consistent with the rest of this library, not
; a hidden gap.
;
; Composed error: roughly the sum of log_f32's and exp_f32's own relative
; error (~1e-7 to ~1e-8 each), so expect pow's result to carry a couple of
; extra ULP versus a dedicated single-pass implementation.
; =============================================================================

bits 64

section .rodata
align 16
powf32_one:        dd 1.0
powf32_nan_bits:   dd 0x7FC00000
powf32_pos_inf:    dd 0x7F800000

; xorps operates on the full 128 bits and requires its memory operand
; 16-byte aligned, so this needs all four lanes and its own alignment —
; a single dd here would fault (not just read garbage) the way a bare
; dd 0x80000000 originally did.
align 16
powf32_sign_mask:  dd 0x80000000, 0x80000000, 0x80000000, 0x80000000

section .text

; -----------------------------------------------------------------------------
; umath_pow_f32 - scalar single-precision x^y
; args:    xmm0 = base (x)
;          xmm1 = exponent (y)
; returns: xmm0 = x^y
; -----------------------------------------------------------------------------
global umath_pow_f32
umath_pow_f32:
    xorps   xmm2, xmm2

    ; ucomiss sets ZF=1 for both "equal" and "unordered" (NaN) outcomes, so
    ; je alone can't tell "y == 0" from "y is NaN" — jp must be checked
    ; first and route around the je, or pow(x, NaN) would wrongly return 1.
    ucomiss xmm1, xmm2
    jp      .y_not_zero
    je      .return_one           ; y == 0 -> 1, for any x (including NaN)
.y_not_zero:

    movss   xmm3, [rel powf32_one]
    ucomiss xmm0, xmm3
    jp      .x_not_one
    je      .return_one           ; x == 1 -> 1, for any y (including NaN)
.x_not_one:

    ucomiss xmm0, xmm0
    jp      .return_nan          ; x is NaN
    ucomiss xmm1, xmm1
    jp      .return_nan          ; y is NaN

    ucomiss xmm0, xmm2
    jne     .x_nonzero

    ; x == 0, y != 0
    ucomiss xmm1, xmm2
    ja      .return_zero         ; y > 0 -> 0
    movss   xmm0, [rel powf32_pos_inf]
    ret                          ; y < 0 -> +Inf (genuine pole)

.x_nonzero:
    ucomiss xmm0, xmm2
    jae     .x_positive          ; x > 0 (x == 0 already handled above)

    ; x < 0: only defined for integer y
    roundss xmm4, xmm1, 0
    ucomiss xmm4, xmm1
    jne     .return_nan          ; y is not an integer

    cvttss2si eax, xmm4          ; exact: xmm4 already holds an integral value
    and     eax, 1
    push    rax                  ; spill parity across the calls below

    xorps   xmm0, [rel powf32_sign_mask]  ; xmm0 = |x| (x < 0 here)

    sub     rsp, 8
    movss   [rsp], xmm1
    call    umath_log_f32
    movss   xmm1, [rsp]
    add     rsp, 8
    mulss   xmm0, xmm1
    call    umath_exp_f32        ; xmm0 = |x|^y

    pop     rax
    test    eax, eax
    jz      .done
    xorps   xmm0, [rel powf32_sign_mask]  ; odd y: negate
.done:
    ret

.x_positive:
    sub     rsp, 8
    movss   [rsp], xmm1
    call    umath_log_f32
    movss   xmm1, [rsp]
    add     rsp, 8
    mulss   xmm0, xmm1
    call    umath_exp_f32
    ret

.return_one:
    movss   xmm0, [rel powf32_one]
    ret

.return_zero:
    xorps   xmm0, xmm0
    ret

.return_nan:
    mov     eax, [rel powf32_nan_bits]
    movd    xmm0, eax
    ret

; -----------------------------------------------------------------------------
; umath_pow_f32_array - x^y elementwise for two arrays of floats
; args:    rdi = destination pointer (dst)
;          rsi = base array pointer (xs)
;          rdx = exponent array pointer (ys)
;          rcx = size of arrays (count)
; returns: void
;
; count is moved out of rcx into r10 immediately: umath_log_f32 (reached
; through umath_pow_f32) clobbers ecx internally, which would otherwise
; corrupt the loop counter on the very first iteration.
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

    mov     r10, rcx

.loop:
    movss   xmm0, [rsi]
    movss   xmm1, [rdx]
    call    umath_pow_f32
    movss   [rdi], xmm0
    add     rsi, 4
    add     rdx, 4
    add     rdi, 4
    dec     r10
    jnz     .loop

.done:
    ret

%endif ; GUARD_LIB_UMATH_MATH_FN_POW_F32_ASM
