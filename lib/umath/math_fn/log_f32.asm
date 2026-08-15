%ifndef GUARD_LIB_UMATH_MATH_FN_LOG_F32_ASM
%define GUARD_LIB_UMATH_MATH_FN_LOG_F32_ASM
; =============================================================================
; umath - unified math library
; math_fn/log_f32.asm - single-precision natural logarithm (ln x)
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; Algorithm (atanh-series range reduction):
;
;   1. Decompose x = m * 2^k via the IEEE-754 bit pattern directly: mask out
;      the exponent field's 8 bits for k (bias 127), then force the field
;      back to 127 to leave m in [1, 2).
;   2. If m > sqrt(2), halve m and increment k, so m lands in the tighter,
;      symmetric-around-1 range [sqrt(2)/2, sqrt(2)). This is what keeps the
;      series in step 3 short.
;   3. s = (m-1)/(m+1) puts the input to the classic atanh series in
;      [-0.1716, 0.1716]:
;        ln(m) = 2*atanh(s) = 2*(s + s^3/3 + s^5/5 + s^7/7 + s^9/9 + s^11/11)
;      evaluated as s * horner(s^2) so the recurring `s` factors out.
;      6 terms is enough headroom for float precision on this range.
;   4. result = k*ln(2) + ln(m).
;
; Domain: ln(0) = -Inf, ln(negative) = NaN, ln(NaN) = NaN, ln(+Inf) = +Inf,
; matching libm.
; This branches per the scalar domain check below, which is why the
; array/inplace paths in this file call the scalar routine per element
; instead of running a branchless packed reduction the way exp_f32.asm
; does — exp only ever needed a branchless clamp, log needs a real
; per-element domain decision, and getting that domain logic right marked
; on 4 lanes at once via blends is not worth the bug surface here.
; =============================================================================

bits 64

section .rodata
align 16
logf32_one:      dd 1.0
logf32_half:     dd 0.5
logf32_sqrt2:    dd 1.4142135623730951
logf32_ln2:       dd 0.6931471805599453
logf32_inv3:       dd 0.3333333333333333
logf32_inv5:       dd 0.2
logf32_inv7:       dd 0.14285714285714285
logf32_inv9:       dd 0.1111111111111111
logf32_inv11:      dd 0.09090909090909091
logf32_nan_bits:   dd 0x7FC00000
logf32_neg_inf_bits: dd 0xFF800000
logf32_flt_min:     dd 1.1754943508222875e-38   ; smallest normal float
logf32_two_pow_25:  dd 33554432.0                ; 2^25, exact power-of-two scale
logf32_pos_inf:     dd 0x7F800000

section .text

; -----------------------------------------------------------------------------
; umath_log_f32 - scalar single-precision natural logarithm
; args:    xmm0 = input value (val)
; returns: xmm0 = ln(val); -Inf for 0, NaN for negative input or NaN input
; -----------------------------------------------------------------------------
global umath_log_f32
umath_log_f32:
    xorps   xmm5, xmm5
    ucomiss xmm0, xmm5
    jp      .return_nan          ; unordered => val is NaN
    ja      .positive            ; val > 0.0

    je      .return_neg_inf      ; val == 0.0
    ; val < 0.0
.return_nan:
    mov     eax, [rel logf32_nan_bits]
    movd    xmm0, eax
    ret

.return_neg_inf:
    mov     eax, [rel logf32_neg_inf_bits]
    movd    xmm0, eax
    ret

.return_pos_inf:
    movss   xmm0, [rel logf32_pos_inf]
    ret

.positive:
    ; +Inf has an all-1s exponent field, which the bit-extraction below
    ; would otherwise silently read as an ordinary (very large) finite
    ; exponent and return a wrong finite answer for.
    ucomiss xmm0, [rel logf32_pos_inf]
    je      .return_pos_inf

    ; Subnormal input (below the smallest normal float) has an all-zero
    ; exponent field, which breaks the implicit-leading-1 assumption the
    ; bit extraction below relies on. Scale it into the normal range by an
    ; exact power of two first, and correct k for that scale afterward.
    xor     r8d, r8d
    comiss  xmm0, [rel logf32_flt_min]
    jae     .extract
    mulss   xmm0, [rel logf32_two_pow_25]
    mov     r8d, 25
.extract:
    movd    eax, xmm0            ; raw IEEE-754 bits (now guaranteed normal)
    mov     ecx, eax
    shr     ecx, 23
    and     ecx, 0xFF
    sub     ecx, 127             ; ecx = k (unbiased exponent)
    sub     ecx, r8d             ; undo the subnormal pre-scale, if any

    and     eax, 0x007FFFFF
    or      eax, (127 << 23)
    movd    xmm1, eax            ; xmm1 = m, in [1, 2)

    movss   xmm2, [rel logf32_sqrt2]
    comiss  xmm1, xmm2
    jbe     .no_adjust
    mulss   xmm1, [rel logf32_half]
    inc     ecx
.no_adjust:
    cvtsi2ss xmm3, ecx           ; xmm3 = (float)k

    movss   xmm4, xmm1
    subss   xmm4, [rel logf32_one]  ; m - 1
    movss   xmm5, xmm1
    addss   xmm5, [rel logf32_one]  ; m + 1
    divss   xmm4, xmm5           ; xmm4 = s = (m-1)/(m+1)

    movss   xmm5, xmm4
    mulss   xmm5, xmm4           ; xmm5 = s^2

    movss   xmm6, [rel logf32_inv11]
    mulss   xmm6, xmm5
    addss   xmm6, [rel logf32_inv9]
    mulss   xmm6, xmm5
    addss   xmm6, [rel logf32_inv7]
    mulss   xmm6, xmm5
    addss   xmm6, [rel logf32_inv5]
    mulss   xmm6, xmm5
    addss   xmm6, [rel logf32_inv3]
    mulss   xmm6, xmm5
    addss   xmm6, [rel logf32_one]
    mulss   xmm6, xmm4            ; xmm6 = s + s^3/3 + ... + s^11/11

    addss   xmm6, xmm6            ; xmm6 = 2*atanh(s) = ln(m)

    mulss   xmm3, [rel logf32_ln2]  ; k * ln(2)
    addss   xmm6, xmm3
    movaps  xmm0, xmm6
    ret

; -----------------------------------------------------------------------------
; umath_log_f32_array - ln(x) for an array of floats
; args:    rdi = destination pointer (dst)
;          rsi = source pointer (src)
;          rdx = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_log_f32_array
umath_log_f32_array:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done
    test    rdx, rdx
    jz      .done

.loop:
    movss   xmm0, [rsi]
    call    umath_log_f32
    movss   [rdi], xmm0
    add     rsi, 4
    add     rdi, 4
    dec     rdx
    jnz     .loop

.done:
    ret

; -----------------------------------------------------------------------------
; umath_log_f32_inplace - ln(x) in place for a float array
; args:    rdi = buffer pointer (buf)
;          rsi = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_log_f32_inplace
umath_log_f32_inplace:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done

.loop:
    movss   xmm0, [rdi]
    call    umath_log_f32
    movss   [rdi], xmm0
    add     rdi, 4
    dec     rsi
    jnz     .loop

.done:
    ret

%endif ; GUARD_LIB_UMATH_MATH_FN_LOG_F32_ASM
