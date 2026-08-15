%ifndef GUARD_LIB_UMATH_MATH_FN_COS_F32_ASM
%define GUARD_LIB_UMATH_MATH_FN_COS_F32_ASM
; =============================================================================
; umath - unified math library
; math_fn/cos_f32.asm - single-precision cosine
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; Same algorithm as sin_f32.asm — quadrant range reduction (done in double
; precision, narrowed to float32 only for the polynomial — see that file's
; header comment for why) + Taylor series on both sin(r) and cos(r), then
; select by n mod 4 from the cosine quadrant table:
;
;   n mod 4 = 0:  cos(x) =  cos(r)
;   n mod 4 = 1:  cos(x) = -sin(r)
;   n mod 4 = 2:  cos(x) = -cos(r)
;   n mod 4 = 3:  cos(x) =  sin(r)
;
; Domain: same practical accuracy bound as sin_f32.asm/sin_f64.asm —
; accurate for |x| up to roughly 2^32 * pi/2 =~ 6.7e9.
;
; cos(NaN) = NaN, cos(±Inf) = NaN (undefined), matching libm.
; =============================================================================

bits 64

section .rodata
align 16
cosf32_two_over_pi_d:  dq 0.6366197723675814
cosf32_pi2_hi_d:        dq 1.5707963267341256
cosf32_pi2_lo_d:        dq 6.077094383272197e-11
cosf32_nan_bits:      dd 0x7FC00000
cosf32_pos_inf:       dd 0x7F800000

align 16
cosf32_sign_mask:     dd 0x80000000, 0x80000000, 0x80000000, 0x80000000

; sin(r) = r + c1*r^3 + c2*r^5 + c3*r^7 + c4*r^9 + c5*r^11
cosf32_sc1:  dd -0.16666666666666666
cosf32_sc2:  dd 0.008333333333333333
cosf32_sc3:  dd -0.0001984126984126984
cosf32_sc4:  dd 2.7557319223985893e-06
cosf32_sc5:  dd -2.505210838544172e-08

; cos(r) = 1 + c1*r^2 + c2*r^4 + c3*r^6 + c4*r^8 + c5*r^10
cosf32_cc1:  dd -0.5
cosf32_cc2:  dd 0.041666666666666664
cosf32_cc3:  dd -0.001388888888888889
cosf32_cc4:  dd 2.48015873015873e-05
cosf32_cc5:  dd -2.755731922398589e-07

cosf32_one:  dd 1.0

section .text

; -----------------------------------------------------------------------------
; umath_cos_f32 - scalar single-precision cosine
; args:    xmm0 = input value (x), radians
; returns: xmm0 = cos(x); NaN for NaN or +/-Inf input
; -----------------------------------------------------------------------------
global umath_cos_f32
umath_cos_f32:
    ucomiss xmm0, xmm0
    jp      .return_nan           ; x is NaN

    movd    eax, xmm0
    and     eax, 0x7FFFFFFF
    movd    xmm6, eax              ; xmm6 = |x|
    ucomiss xmm6, [rel cosf32_pos_inf]
    je      .return_nan            ; |x| == Inf (cos(Inf) is undefined)

    cvtss2sd xmm0, xmm0             ; widen x to double for the reduction

    movsd   xmm1, [rel cosf32_two_over_pi_d]
    mulsd   xmm1, xmm0
    roundsd xmm1, xmm1, 0          ; xmm1 = n (double, round to nearest)

    movsd   xmm2, xmm1
    mulsd   xmm2, [rel cosf32_pi2_hi_d]
    subsd   xmm0, xmm2
    movsd   xmm2, xmm1
    mulsd   xmm2, [rel cosf32_pi2_lo_d]
    subsd   xmm0, xmm2             ; xmm0 = r (double)

    cvtsd2ss xmm0, xmm0             ; narrow r back to float32 for the polynomial

    movss   xmm2, xmm0
    mulss   xmm2, xmm0              ; xmm2 = r^2

    ; sin(r) in xmm3
    movss   xmm3, [rel cosf32_sc5]
    mulss   xmm3, xmm2
    addss   xmm3, [rel cosf32_sc4]
    mulss   xmm3, xmm2
    addss   xmm3, [rel cosf32_sc3]
    mulss   xmm3, xmm2
    addss   xmm3, [rel cosf32_sc2]
    mulss   xmm3, xmm2
    addss   xmm3, [rel cosf32_sc1]
    mulss   xmm3, xmm2
    addss   xmm3, [rel cosf32_one]
    mulss   xmm3, xmm0              ; xmm3 = sin(r)

    ; cos(r) in xmm4
    movss   xmm4, [rel cosf32_cc5]
    mulss   xmm4, xmm2
    addss   xmm4, [rel cosf32_cc4]
    mulss   xmm4, xmm2
    addss   xmm4, [rel cosf32_cc3]
    mulss   xmm4, xmm2
    addss   xmm4, [rel cosf32_cc2]
    mulss   xmm4, xmm2
    addss   xmm4, [rel cosf32_cc1]
    mulss   xmm4, xmm2
    addss   xmm4, [rel cosf32_one]  ; xmm4 = cos(r)

    cvttsd2si eax, xmm1             ; n is already integral; truncate is exact
    and     eax, 3

    cmp     eax, 0
    je      .quad0
    cmp     eax, 1
    je      .quad1
    cmp     eax, 2
    je      .quad2
    ; quad 3: sin(r)
    movaps  xmm0, xmm3
    ret
.quad0:
    movaps  xmm0, xmm4
    ret
.quad1:
    xorps   xmm3, [rel cosf32_sign_mask]
    movaps  xmm0, xmm3
    ret
.quad2:
    xorps   xmm4, [rel cosf32_sign_mask]
    movaps  xmm0, xmm4
    ret

.return_nan:
    mov     eax, [rel cosf32_nan_bits]
    movd    xmm0, eax
    ret

; -----------------------------------------------------------------------------
; umath_cos_f32_array - cos(x) for an array of floats
; args:    rdi = destination pointer (dst)
;          rsi = source pointer (src)
;          rdx = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_cos_f32_array
umath_cos_f32_array:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done
    test    rdx, rdx
    jz      .done

.loop:
    movss   xmm0, [rsi]
    call    umath_cos_f32
    movss   [rdi], xmm0
    add     rsi, 4
    add     rdi, 4
    dec     rdx
    jnz     .loop

.done:
    ret

; -----------------------------------------------------------------------------
; umath_cos_f32_inplace - cos(x) in place for a float array
; args:    rdi = buffer pointer (buf)
;          rsi = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_cos_f32_inplace
umath_cos_f32_inplace:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done

.loop:
    movss   xmm0, [rdi]
    call    umath_cos_f32
    movss   [rdi], xmm0
    add     rdi, 4
    dec     rsi
    jnz     .loop

.done:
    ret

%endif ; GUARD_LIB_UMATH_MATH_FN_COS_F32_ASM
