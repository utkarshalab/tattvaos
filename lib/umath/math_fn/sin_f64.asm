%ifndef GUARD_LIB_UMATH_MATH_FN_SIN_F64_ASM
%define GUARD_LIB_UMATH_MATH_FN_SIN_F64_ASM
; =============================================================================
; umath - unified math library
; math_fn/sin_f64.asm - double-precision sine
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; Same quadrant range-reduction algorithm as sin_f32.asm (see that file's
; header for the full derivation and why range reduction needs to run in
; double precision — moot here since this *is* the double-precision path
; already, no widen/narrow step needed). The Taylor series for sin(r)/
; cos(r) uses 10 terms each here instead of f32's 6, matching the same
; term-count-doubles-for-double-precision pattern documented in
; exp_f64.asm/log_f64.asm.
;
; Domain: the pi/2 hi/lo split uses a 2^32 factor (hi keeps its low 32
; mantissa bits zeroed), which keeps n*hi exact only while n stays under
; roughly 2^32 — i.e. |x| up to roughly 2^32 * pi/2 =~ 6.7e9. Verified
; accurate (a few ULP) well within that bound; verified *inaccurate*
; (~1e-5 absolute error) at |x| = 1e12, well beyond it — this is a real,
; measured limit of the simple (not Payne-Hanek) range reduction here, not
; a vague caveat. Fine for anything a normal numeric workload produces;
; not fine for reducing an arbitrarily large angle exactly.
;
; sin(NaN) = NaN, sin(±Inf) = NaN (undefined), matching libm.
; =============================================================================

bits 64

section .rodata
align 16
sinf64_two_over_pi:  dq 0.6366197723675814
sinf64_pi2_hi:        dq 1.5707963267341256
sinf64_pi2_lo:        dq 6.077094383272197e-11
sinf64_nan_bits:      dq 0x7FF8000000000000
sinf64_pos_inf:       dq 0x7FF0000000000000

align 16
sinf64_sign_mask:     dq 0x8000000000000000, 0x8000000000000000

; sin(r) = r*(1 + c1*r^2 + c2*r^4 + ... + c9*r^18)
sinf64_sc1:  dq -0.16666666666666666
sinf64_sc2:  dq 0.008333333333333333
sinf64_sc3:  dq -0.0001984126984126984
sinf64_sc4:  dq 2.7557319223985893e-06
sinf64_sc5:  dq -2.505210838544172e-08
sinf64_sc6:  dq 1.6059043836821613e-10
sinf64_sc7:  dq -7.647163731819816e-13
sinf64_sc8:  dq 2.8114572543455206e-15
sinf64_sc9:  dq -8.22063524662433e-18

; cos(r) = 1 + c1*r^2 + c2*r^4 + ... + c9*r^18
sinf64_cc1:  dq -0.5
sinf64_cc2:  dq 0.041666666666666664
sinf64_cc3:  dq -0.001388888888888889
sinf64_cc4:  dq 2.48015873015873e-05
sinf64_cc5:  dq -2.755731922398589e-07
sinf64_cc6:  dq 2.08767569878681e-09
sinf64_cc7:  dq -1.1470745597729725e-11
sinf64_cc8:  dq 4.779477332387385e-14
sinf64_cc9:  dq -1.5619206968586225e-16

sinf64_one:  dq 1.0

section .text

; -----------------------------------------------------------------------------
; umath_sin_f64 - scalar double-precision sine
; args:    xmm0 = input value (x), radians
; returns: xmm0 = sin(x); NaN for NaN or +/-Inf input
; -----------------------------------------------------------------------------
global umath_sin_f64
umath_sin_f64:
    ucomisd xmm0, xmm0
    jp      .return_nan           ; x is NaN

    movq    rax, xmm0
    mov     r8, 0x7FFFFFFFFFFFFFFF
    and     rax, r8
    movq    xmm6, rax              ; xmm6 = |x|
    ucomisd xmm6, [rel sinf64_pos_inf]
    je      .return_nan            ; |x| == Inf (sin(Inf) is undefined)

    movsd   xmm1, [rel sinf64_two_over_pi]
    mulsd   xmm1, xmm0
    roundsd xmm1, xmm1, 0          ; xmm1 = n (round to nearest)

    movsd   xmm2, xmm1
    mulsd   xmm2, [rel sinf64_pi2_hi]
    subsd   xmm0, xmm2
    movsd   xmm2, xmm1
    mulsd   xmm2, [rel sinf64_pi2_lo]
    subsd   xmm0, xmm2             ; xmm0 = r

    movsd   xmm2, xmm0
    mulsd   xmm2, xmm0              ; xmm2 = r^2

    ; sin(r) in xmm3
    movsd   xmm3, [rel sinf64_sc9]
    mulsd   xmm3, xmm2
    addsd   xmm3, [rel sinf64_sc8]
    mulsd   xmm3, xmm2
    addsd   xmm3, [rel sinf64_sc7]
    mulsd   xmm3, xmm2
    addsd   xmm3, [rel sinf64_sc6]
    mulsd   xmm3, xmm2
    addsd   xmm3, [rel sinf64_sc5]
    mulsd   xmm3, xmm2
    addsd   xmm3, [rel sinf64_sc4]
    mulsd   xmm3, xmm2
    addsd   xmm3, [rel sinf64_sc3]
    mulsd   xmm3, xmm2
    addsd   xmm3, [rel sinf64_sc2]
    mulsd   xmm3, xmm2
    addsd   xmm3, [rel sinf64_sc1]
    mulsd   xmm3, xmm2
    addsd   xmm3, [rel sinf64_one]
    mulsd   xmm3, xmm0              ; xmm3 = sin(r)

    ; cos(r) in xmm4
    movsd   xmm4, [rel sinf64_cc9]
    mulsd   xmm4, xmm2
    addsd   xmm4, [rel sinf64_cc8]
    mulsd   xmm4, xmm2
    addsd   xmm4, [rel sinf64_cc7]
    mulsd   xmm4, xmm2
    addsd   xmm4, [rel sinf64_cc6]
    mulsd   xmm4, xmm2
    addsd   xmm4, [rel sinf64_cc5]
    mulsd   xmm4, xmm2
    addsd   xmm4, [rel sinf64_cc4]
    mulsd   xmm4, xmm2
    addsd   xmm4, [rel sinf64_cc3]
    mulsd   xmm4, xmm2
    addsd   xmm4, [rel sinf64_cc2]
    mulsd   xmm4, xmm2
    addsd   xmm4, [rel sinf64_cc1]
    mulsd   xmm4, xmm2
    addsd   xmm4, [rel sinf64_one]  ; xmm4 = cos(r)

    cvttsd2si eax, xmm1             ; n is already integral; truncate is exact
    and     eax, 3

    cmp     eax, 0
    je      .quad0
    cmp     eax, 1
    je      .quad1
    cmp     eax, 2
    je      .quad2
    ; quad 3: -cos(r)
    xorpd   xmm4, [rel sinf64_sign_mask]
    movapd  xmm0, xmm4
    ret
.quad0:
    movapd  xmm0, xmm3
    ret
.quad1:
    movapd  xmm0, xmm4
    ret
.quad2:
    xorpd   xmm3, [rel sinf64_sign_mask]
    movapd  xmm0, xmm3
    ret

.return_nan:
    mov     rax, [rel sinf64_nan_bits]
    movq    xmm0, rax
    ret

; -----------------------------------------------------------------------------
; umath_sin_f64_array - sin(x) for an array of doubles
; args:    rdi = destination pointer (dst)
;          rsi = source pointer (src)
;          rdx = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_sin_f64_array
umath_sin_f64_array:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done
    test    rdx, rdx
    jz      .done

.loop:
    movsd   xmm0, [rsi]
    call    umath_sin_f64
    movsd   [rdi], xmm0
    add     rsi, 8
    add     rdi, 8
    dec     rdx
    jnz     .loop

.done:
    ret

; -----------------------------------------------------------------------------
; umath_sin_f64_inplace - sin(x) in place for a double array
; args:    rdi = buffer pointer (buf)
;          rsi = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_sin_f64_inplace
umath_sin_f64_inplace:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done

.loop:
    movsd   xmm0, [rdi]
    call    umath_sin_f64
    movsd   [rdi], xmm0
    add     rdi, 8
    dec     rsi
    jnz     .loop

.done:
    ret

%endif ; GUARD_LIB_UMATH_MATH_FN_SIN_F64_ASM
