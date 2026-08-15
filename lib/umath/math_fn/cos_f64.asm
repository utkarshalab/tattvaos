%ifndef GUARD_LIB_UMATH_MATH_FN_COS_F64_ASM
%define GUARD_LIB_UMATH_MATH_FN_COS_F64_ASM
; =============================================================================
; umath - unified math library
; math_fn/cos_f64.asm - double-precision cosine
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; Same algorithm as sin_f64.asm — quadrant range reduction + 10-term
; Taylor series on both sin(r) and cos(r), then select by n mod 4 from
; the cosine quadrant table:
;
;   n mod 4 = 0:  cos(x) =  cos(r)
;   n mod 4 = 1:  cos(x) = -sin(r)
;   n mod 4 = 2:  cos(x) = -cos(r)
;   n mod 4 = 3:  cos(x) =  sin(r)
;
; Domain: same practical accuracy bound as sin_f64.asm — accurate for
; |x| up to roughly 2^32 * pi/2 =~ 6.7e9, measurably degraded well beyond
; it. See that file's header for the measured numbers.
;
; cos(NaN) = NaN, cos(±Inf) = NaN (undefined), matching libm.
; =============================================================================

bits 64

section .rodata
align 16
cosf64_two_over_pi:  dq 0.6366197723675814
cosf64_pi2_hi:        dq 1.5707963267341256
cosf64_pi2_lo:        dq 6.077094383272197e-11
cosf64_nan_bits:      dq 0x7FF8000000000000
cosf64_pos_inf:       dq 0x7FF0000000000000

align 16
cosf64_sign_mask:     dq 0x8000000000000000, 0x8000000000000000

cosf64_sc1:  dq -0.16666666666666666
cosf64_sc2:  dq 0.008333333333333333
cosf64_sc3:  dq -0.0001984126984126984
cosf64_sc4:  dq 2.7557319223985893e-06
cosf64_sc5:  dq -2.505210838544172e-08
cosf64_sc6:  dq 1.6059043836821613e-10
cosf64_sc7:  dq -7.647163731819816e-13
cosf64_sc8:  dq 2.8114572543455206e-15
cosf64_sc9:  dq -8.22063524662433e-18

cosf64_cc1:  dq -0.5
cosf64_cc2:  dq 0.041666666666666664
cosf64_cc3:  dq -0.001388888888888889
cosf64_cc4:  dq 2.48015873015873e-05
cosf64_cc5:  dq -2.755731922398589e-07
cosf64_cc6:  dq 2.08767569878681e-09
cosf64_cc7:  dq -1.1470745597729725e-11
cosf64_cc8:  dq 4.779477332387385e-14
cosf64_cc9:  dq -1.5619206968586225e-16

cosf64_one:  dq 1.0

section .text

; -----------------------------------------------------------------------------
; umath_cos_f64 - scalar double-precision cosine
; args:    xmm0 = input value (x), radians
; returns: xmm0 = cos(x); NaN for NaN or +/-Inf input
; -----------------------------------------------------------------------------
global umath_cos_f64
umath_cos_f64:
    ucomisd xmm0, xmm0
    jp      .return_nan           ; x is NaN

    movq    rax, xmm0
    mov     r8, 0x7FFFFFFFFFFFFFFF
    and     rax, r8
    movq    xmm6, rax              ; xmm6 = |x|
    ucomisd xmm6, [rel cosf64_pos_inf]
    je      .return_nan            ; |x| == Inf (cos(Inf) is undefined)

    movsd   xmm1, [rel cosf64_two_over_pi]
    mulsd   xmm1, xmm0
    roundsd xmm1, xmm1, 0          ; xmm1 = n (round to nearest)

    movsd   xmm2, xmm1
    mulsd   xmm2, [rel cosf64_pi2_hi]
    subsd   xmm0, xmm2
    movsd   xmm2, xmm1
    mulsd   xmm2, [rel cosf64_pi2_lo]
    subsd   xmm0, xmm2             ; xmm0 = r

    movsd   xmm2, xmm0
    mulsd   xmm2, xmm0              ; xmm2 = r^2

    ; sin(r) in xmm3
    movsd   xmm3, [rel cosf64_sc9]
    mulsd   xmm3, xmm2
    addsd   xmm3, [rel cosf64_sc8]
    mulsd   xmm3, xmm2
    addsd   xmm3, [rel cosf64_sc7]
    mulsd   xmm3, xmm2
    addsd   xmm3, [rel cosf64_sc6]
    mulsd   xmm3, xmm2
    addsd   xmm3, [rel cosf64_sc5]
    mulsd   xmm3, xmm2
    addsd   xmm3, [rel cosf64_sc4]
    mulsd   xmm3, xmm2
    addsd   xmm3, [rel cosf64_sc3]
    mulsd   xmm3, xmm2
    addsd   xmm3, [rel cosf64_sc2]
    mulsd   xmm3, xmm2
    addsd   xmm3, [rel cosf64_sc1]
    mulsd   xmm3, xmm2
    addsd   xmm3, [rel cosf64_one]
    mulsd   xmm3, xmm0              ; xmm3 = sin(r)

    ; cos(r) in xmm4
    movsd   xmm4, [rel cosf64_cc9]
    mulsd   xmm4, xmm2
    addsd   xmm4, [rel cosf64_cc8]
    mulsd   xmm4, xmm2
    addsd   xmm4, [rel cosf64_cc7]
    mulsd   xmm4, xmm2
    addsd   xmm4, [rel cosf64_cc6]
    mulsd   xmm4, xmm2
    addsd   xmm4, [rel cosf64_cc5]
    mulsd   xmm4, xmm2
    addsd   xmm4, [rel cosf64_cc4]
    mulsd   xmm4, xmm2
    addsd   xmm4, [rel cosf64_cc3]
    mulsd   xmm4, xmm2
    addsd   xmm4, [rel cosf64_cc2]
    mulsd   xmm4, xmm2
    addsd   xmm4, [rel cosf64_cc1]
    mulsd   xmm4, xmm2
    addsd   xmm4, [rel cosf64_one]  ; xmm4 = cos(r)

    cvttsd2si eax, xmm1             ; n is already integral; truncate is exact
    and     eax, 3

    cmp     eax, 0
    je      .quad0
    cmp     eax, 1
    je      .quad1
    cmp     eax, 2
    je      .quad2
    ; quad 3: sin(r)
    movapd  xmm0, xmm3
    ret
.quad0:
    movapd  xmm0, xmm4
    ret
.quad1:
    xorpd   xmm3, [rel cosf64_sign_mask]
    movapd  xmm0, xmm3
    ret
.quad2:
    xorpd   xmm4, [rel cosf64_sign_mask]
    movapd  xmm0, xmm4
    ret

.return_nan:
    mov     rax, [rel cosf64_nan_bits]
    movq    xmm0, rax
    ret

; -----------------------------------------------------------------------------
; umath_cos_f64_array - cos(x) for an array of doubles
; args:    rdi = destination pointer (dst)
;          rsi = source pointer (src)
;          rdx = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_cos_f64_array
umath_cos_f64_array:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done
    test    rdx, rdx
    jz      .done

.loop:
    movsd   xmm0, [rsi]
    call    umath_cos_f64
    movsd   [rdi], xmm0
    add     rsi, 8
    add     rdi, 8
    dec     rdx
    jnz     .loop

.done:
    ret

; -----------------------------------------------------------------------------
; umath_cos_f64_inplace - cos(x) in place for a double array
; args:    rdi = buffer pointer (buf)
;          rsi = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_cos_f64_inplace
umath_cos_f64_inplace:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done

.loop:
    movsd   xmm0, [rdi]
    call    umath_cos_f64
    movsd   [rdi], xmm0
    add     rdi, 8
    dec     rsi
    jnz     .loop

.done:
    ret

%endif ; GUARD_LIB_UMATH_MATH_FN_COS_F64_ASM
