%ifndef GUARD_LIB_UMATH_MATH_FN_EXP_F32_ASM
%define GUARD_LIB_UMATH_MATH_FN_EXP_F32_ASM
; =============================================================================
; umath - unified math library
; math_fn/exp_f32.asm - single-precision natural exponential (e^x)
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; Algorithm (standard range-reduction + minimax polynomial, the same shape
; used by fdlibm/cephes-derived libm implementations):
;
;   1. Clamp x to [MINLOGF, MAXLOGF] = [-104, 89], just past the points where
;      e^x underflows to 0 and overflows to +Inf, so k (below) stays within
;      [-150, 128]. The clamp keeps NaN: the constant is the first operand of
;      minss/maxss, which return their second operand on unordered input.
;   2. k = round_to_nearest(x * log2(e))          ; integer power-of-two part
;   3. r = x - k*C1 - k*C2                        ; reduced argument, |r| small
;      (ln(2) is split into a hi/lo pair C1+C2 so the subtraction doesn't
;      lose the low bits that k*ln(2) would otherwise wash out)
;   4. p(r) = degree-5 minimax polynomial approximating exp(r) on the
;      reduced range, evaluated by Horner's method
;   5. result = p(r) * 2^k1 * 2^k2 with k1 = k >> 1 and k2 = k - k1, each
;      power of two built directly as IEEE-754 bits (k biased by 127 and
;      shifted into place). Splitting k keeps both factors normal, so the
;      first multiply is exact and the second rounds once: results past
;      FLT_MAX become +Inf and tiny results round through subnormals to 0.
;
; Design & Optimization:
;   - Scalar path operates on a single lane (xmm0).
;   - Array/inplace paths run the identical algorithm 4-wide with packed
;     single ops (addps/mulps/roundps/cvtps2dq/pslld/paddd), unrolled to
;     process 8 floats (two xmm regs) per iteration, with a residual tail.
; =============================================================================

bits 64

section .rodata
align 16
expf32_log2ef:  dd 1.44269504088896341, 1.44269504088896341, 1.44269504088896341, 1.44269504088896341
expf32_c1:       dd 0.693359375, 0.693359375, 0.693359375, 0.693359375
expf32_c2:       dd -2.12194440e-4, -2.12194440e-4, -2.12194440e-4, -2.12194440e-4
expf32_p0:        dd 1.9875691500e-4, 1.9875691500e-4, 1.9875691500e-4, 1.9875691500e-4
expf32_p1:        dd 1.3981999507e-3, 1.3981999507e-3, 1.3981999507e-3, 1.3981999507e-3
expf32_p2:        dd 8.3334519073e-3, 8.3334519073e-3, 8.3334519073e-3, 8.3334519073e-3
expf32_p3:        dd 4.1665795894e-2, 4.1665795894e-2, 4.1665795894e-2, 4.1665795894e-2
expf32_p4:        dd 1.6666665459e-1, 1.6666665459e-1, 1.6666665459e-1, 1.6666665459e-1
expf32_p5:        dd 5.0000001201e-1, 5.0000001201e-1, 5.0000001201e-1, 5.0000001201e-1
expf32_one:       dd 1.0, 1.0, 1.0, 1.0
expf32_maxlogf:   dd 89.0, 89.0, 89.0, 89.0          ; > ln(FLT_MAX) = 88.72: overflows to +Inf
expf32_minlogf:   dd -104.0, -104.0, -104.0, -104.0  ; < ln(2^-150) = -103.97: underflows to 0
expf32_bias_i32:      dd 127, 127, 127, 127

section .text

; -----------------------------------------------------------------------------
; umath_exp_f32 - scalar single-precision e^x
; args:    xmm0 = input value (x)
; returns: xmm0 = e^x (+Inf on overflow, 0 or subnormal on underflow, NaN
;          for NaN input)
; -----------------------------------------------------------------------------
global umath_exp_f32
umath_exp_f32:
    movss   xmm1, [rel expf32_maxlogf]
    minss   xmm1, xmm0           ; NaN x comes back as x (second operand)
    movss   xmm0, [rel expf32_minlogf]
    maxss   xmm0, xmm1           ; xmm0 = x clamped to [MINLOGF, MAXLOGF]

    movss   xmm1, [rel expf32_log2ef]
    mulss   xmm1, xmm0
    roundss xmm1, xmm1, 0        ; xmm1 = k (round to nearest)

    movss   xmm2, xmm1
    mulss   xmm2, [rel expf32_c1]
    subss   xmm0, xmm2           ; x -= k*C1
    movss   xmm2, xmm1
    mulss   xmm2, [rel expf32_c2]
    subss   xmm0, xmm2           ; x -= k*C2  (xmm0 = r)

    movss   xmm2, [rel expf32_p0]
    mulss   xmm2, xmm0
    addss   xmm2, [rel expf32_p1]
    mulss   xmm2, xmm0
    addss   xmm2, [rel expf32_p2]
    mulss   xmm2, xmm0
    addss   xmm2, [rel expf32_p3]
    mulss   xmm2, xmm0
    addss   xmm2, [rel expf32_p4]
    mulss   xmm2, xmm0
    addss   xmm2, [rel expf32_p5]

    movss   xmm3, xmm0
    mulss   xmm3, xmm0            ; z = r*r
    mulss   xmm2, xmm3             ; p*z
    addss   xmm2, xmm0             ; + r
    addss   xmm2, [rel expf32_one] ; p(r) = p*z + r + 1

    cvttss2si eax, xmm1            ; k is already integral; truncate is exact
    mov     ecx, eax
    sar     ecx, 1                 ; k1 = k >> 1
    sub     eax, ecx               ; k2 = k - k1
    add     ecx, 127
    shl     ecx, 23
    movd    xmm4, ecx              ; xmm4 = bit pattern of 2^k1
    mulss   xmm2, xmm4             ; exact: both factors normal
    add     eax, 127
    shl     eax, 23
    movd    xmm4, eax              ; xmm4 = bit pattern of 2^k2
    mulss   xmm2, xmm4             ; single rounding (overflow/underflow here)

    movaps  xmm0, xmm2
    ret

; -----------------------------------------------------------------------------
; umath_exp_f32_array - e^x for an array of floats
; args:    rdi = destination pointer (dst)
;          rsi = source pointer (src)
;          rdx = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_exp_f32_array
umath_exp_f32_array:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done
    test    rdx, rdx
    jz      .done

    cmp     rdx, 8
    jb      .residuals

    mov     rcx, rdx
    shr     rcx, 3               ; count of 8-float (2x xmm) blocks

.loop_unrolled:
    movups  xmm0, [rsi]
    movups  xmm5, [rsi + 16]
    call    umath_exp_f32__reduce4
    movaps  xmm6, xmm0
    movaps  xmm0, xmm5
    call    umath_exp_f32__reduce4
    movups  [rdi], xmm6
    movups  [rdi + 16], xmm0

    add     rsi, 32
    add     rdi, 32
    dec     rcx
    jnz     .loop_unrolled

    and     rdx, 7
    jz      .done

.residuals:
    movss   xmm0, [rsi]
    call    umath_exp_f32
    movss   [rdi], xmm0
    add     rsi, 4
    add     rdi, 4
    dec     rdx
    jnz     .residuals

.done:
    ret

; -----------------------------------------------------------------------------
; umath_exp_f32__reduce4 - internal helper: packed 4-wide e^x, in place on xmm0
; Not declared global: only callable from within this translation unit.
; Clobbers xmm1-xmm4.
; -----------------------------------------------------------------------------
umath_exp_f32__reduce4:
    movaps  xmm1, [rel expf32_maxlogf]
    minps   xmm1, xmm0           ; NaN lanes come back as x (second operand)
    movaps  xmm0, [rel expf32_minlogf]
    maxps   xmm0, xmm1           ; xmm0 = x clamped to [MINLOGF, MAXLOGF]

    movaps  xmm1, [rel expf32_log2ef]
    mulps   xmm1, xmm0
    roundps xmm1, xmm1, 0        ; xmm1 = k (per lane)

    movaps  xmm2, xmm1
    mulps   xmm2, [rel expf32_c1]
    subps   xmm0, xmm2
    movaps  xmm2, xmm1
    mulps   xmm2, [rel expf32_c2]
    subps   xmm0, xmm2           ; xmm0 = r

    movaps  xmm2, [rel expf32_p0]
    mulps   xmm2, xmm0
    addps   xmm2, [rel expf32_p1]
    mulps   xmm2, xmm0
    addps   xmm2, [rel expf32_p2]
    mulps   xmm2, xmm0
    addps   xmm2, [rel expf32_p3]
    mulps   xmm2, xmm0
    addps   xmm2, [rel expf32_p4]
    mulps   xmm2, xmm0
    addps   xmm2, [rel expf32_p5]

    movaps  xmm3, xmm0
    mulps   xmm3, xmm0
    mulps   xmm2, xmm3
    addps   xmm2, xmm0
    addps   xmm2, [rel expf32_one] ; xmm2 = p(r)

    cvtps2dq xmm4, xmm1           ; k as packed int32 (exact, k already integral)
    movdqa  xmm3, xmm4
    psrad   xmm3, 1               ; k1 = k >> 1
    psubd   xmm4, xmm3            ; k2 = k - k1
    paddd   xmm3, [rel expf32_bias_i32]
    pslld   xmm3, 23              ; xmm3 = bit pattern of 2^k1, per lane
    paddd   xmm4, [rel expf32_bias_i32]
    pslld   xmm4, 23              ; xmm4 = bit pattern of 2^k2, per lane

    mulps   xmm2, xmm3            ; exact: both factors normal
    mulps   xmm2, xmm4            ; single rounding
    movaps  xmm0, xmm2
    ret

; -----------------------------------------------------------------------------
; umath_exp_f32_inplace - e^x in place for a float array
; args:    rdi = buffer pointer (buf)
;          rsi = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_exp_f32_inplace
umath_exp_f32_inplace:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done

    cmp     rsi, 8
    jb      .residuals

    mov     rcx, rsi
    shr     rcx, 3

.loop_unrolled:
    movups  xmm0, [rdi]
    movups  xmm5, [rdi + 16]
    call    umath_exp_f32__reduce4
    movaps  xmm6, xmm0
    movaps  xmm0, xmm5
    call    umath_exp_f32__reduce4
    movups  [rdi], xmm6
    movups  [rdi + 16], xmm0

    add     rdi, 32
    dec     rcx
    jnz     .loop_unrolled

    and     rsi, 7
    jz      .done

.residuals:
    movss   xmm0, [rdi]
    call    umath_exp_f32
    movss   [rdi], xmm0
    add     rdi, 4
    dec     rsi
    jnz     .residuals

.done:
    ret

%endif ; GUARD_LIB_UMATH_MATH_FN_EXP_F32_ASM
