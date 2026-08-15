%ifndef GUARD_LIB_UMATH_MATH_FN_SIN_F32_ASM
%define GUARD_LIB_UMATH_MATH_FN_SIN_F32_ASM
; =============================================================================
; umath - unified math library
; math_fn/sin_f32.asm - single-precision sine
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; Algorithm (quadrant range reduction + Taylor series, same shape as
; math_fn's exp/log range reduction):
;
;   1. n = round(x * 2/pi)              ; nearest multiple of pi/2
;   2. r = x - n*(pi/2)_hi - n*(pi/2)_lo ; reduced argument, |r| <= pi/4,
;      pi/2 split into an exact hi/lo pair the same way ln(2) is in
;      exp_f32.asm
;   3. Evaluate sin(r) and cos(r) both, via Taylor series (6 terms each is
;      enough headroom for float precision on |r| <= pi/4)
;   4. Select the result from n mod 4 from the standard sin/cos quadrant
;      table:
;         n mod 4 = 0:  sin(x) =  sin(r)
;         n mod 4 = 1:  sin(x) =  cos(r)
;         n mod 4 = 2:  sin(x) = -sin(r)
;         n mod 4 = 3:  sin(x) = -cos(r)
;
; Step 1-2 (range reduction) runs in DOUBLE precision even though this is
; the f32 entry point — x is widened via cvtss2sd first, the reduction
; multiply/subtract happens in double, and only the small reduced r gets
; narrowed back to float32 before the polynomial evaluation. This matters:
; the hi/lo split of pi/2 only keeps n*hi exact if hi itself hasn't
; already lost precision to being stored as a single float, and a first
; version of this file that did the whole reduction in float32 was
; measurably wrong (~1.7e-5 absolute error) by x=1000 — not some
; pathological extreme, just because n grows large enough that a
; float32-rounded hi's exactness guarantee had already broken down. This
; is the same fix real sinf/cosf implementations use, not an original
; technique.
;
; Domain: still a simple (not Payne-Hanek) range reduction. The pi/2 hi/lo
; split uses a 2^32 factor, keeping n*hi exact only while n stays under
; roughly 2^32 — i.e. |x| up to roughly 2^32 * pi/2 =~ 6.7e9 (see
; sin_f64.asm's header for the same bound with measured error numbers).
; Not an issue for anything in a normal numeric workload's range; would be
; for something like reducing 1e300 accurately.
;
; sin(NaN) = NaN, sin(±Inf) = NaN (undefined), matching libm.
; =============================================================================

bits 64

section .rodata
align 16
sinf32_two_over_pi_d:  dq 0.6366197723675814
sinf32_pi2_hi_d:        dq 1.5707963267341256
sinf32_pi2_lo_d:        dq 6.077094383272197e-11
sinf32_nan_bits:      dd 0x7FC00000
sinf32_pos_inf:       dd 0x7F800000

; xorps needs its full 128 bits and its own 16-byte alignment (see
; pow_f32.asm's README-documented fix for the same mistake) — the four
; preceding dd's leave this offset unaligned without this.
align 16
sinf32_sign_mask:     dd 0x80000000, 0x80000000, 0x80000000, 0x80000000

; sin(r) = r + c1*r^3 + c2*r^5 + c3*r^7 + c4*r^9 + c5*r^11
sinf32_sc1:  dd -0.16666666666666666
sinf32_sc2:  dd 0.008333333333333333
sinf32_sc3:  dd -0.0001984126984126984
sinf32_sc4:  dd 2.7557319223985893e-06
sinf32_sc5:  dd -2.505210838544172e-08

; cos(r) = 1 + c1*r^2 + c2*r^4 + c3*r^6 + c4*r^8 + c5*r^10
sinf32_cc1:  dd -0.5
sinf32_cc2:  dd 0.041666666666666664
sinf32_cc3:  dd -0.001388888888888889
sinf32_cc4:  dd 2.48015873015873e-05
sinf32_cc5:  dd -2.755731922398589e-07

sinf32_one:  dd 1.0

section .text

; -----------------------------------------------------------------------------
; umath_sin_f32 - scalar single-precision sine
; args:    xmm0 = input value (x), radians
; returns: xmm0 = sin(x); NaN for NaN or +/-Inf input
; -----------------------------------------------------------------------------
global umath_sin_f32
umath_sin_f32:
    ucomiss xmm0, xmm0
    jp      .return_nan           ; x is NaN

    movd    eax, xmm0
    and     eax, 0x7FFFFFFF
    movd    xmm6, eax              ; xmm6 = |x|
    ucomiss xmm6, [rel sinf32_pos_inf]
    je      .return_nan            ; |x| == Inf (sin(Inf) is undefined)

    cvtss2sd xmm0, xmm0             ; widen x to double for the reduction

    movsd   xmm1, [rel sinf32_two_over_pi_d]
    mulsd   xmm1, xmm0
    roundsd xmm1, xmm1, 0          ; xmm1 = n (double, round to nearest)

    movsd   xmm2, xmm1
    mulsd   xmm2, [rel sinf32_pi2_hi_d]
    subsd   xmm0, xmm2
    movsd   xmm2, xmm1
    mulsd   xmm2, [rel sinf32_pi2_lo_d]
    subsd   xmm0, xmm2             ; xmm0 = r (double)

    cvtsd2ss xmm0, xmm0             ; narrow r back to float32 for the polynomial

    movss   xmm2, xmm0
    mulss   xmm2, xmm0              ; xmm2 = r^2

    ; sin(r) in xmm3
    movss   xmm3, [rel sinf32_sc5]
    mulss   xmm3, xmm2
    addss   xmm3, [rel sinf32_sc4]
    mulss   xmm3, xmm2
    addss   xmm3, [rel sinf32_sc3]
    mulss   xmm3, xmm2
    addss   xmm3, [rel sinf32_sc2]
    mulss   xmm3, xmm2
    addss   xmm3, [rel sinf32_sc1]
    mulss   xmm3, xmm2
    addss   xmm3, [rel sinf32_one]
    mulss   xmm3, xmm0              ; xmm3 = sin(r)

    ; cos(r) in xmm4
    movss   xmm4, [rel sinf32_cc5]
    mulss   xmm4, xmm2
    addss   xmm4, [rel sinf32_cc4]
    mulss   xmm4, xmm2
    addss   xmm4, [rel sinf32_cc3]
    mulss   xmm4, xmm2
    addss   xmm4, [rel sinf32_cc2]
    mulss   xmm4, xmm2
    addss   xmm4, [rel sinf32_cc1]
    mulss   xmm4, xmm2
    addss   xmm4, [rel sinf32_one]  ; xmm4 = cos(r)

    cvttsd2si eax, xmm1             ; n is already integral; truncate is exact
    and     eax, 3

    cmp     eax, 0
    je      .quad0
    cmp     eax, 1
    je      .quad1
    cmp     eax, 2
    je      .quad2
    ; quad 3: -cos(r)
    xorps   xmm4, [rel sinf32_sign_mask]
    movaps  xmm0, xmm4
    ret
.quad0:
    movaps  xmm0, xmm3
    ret
.quad1:
    movaps  xmm0, xmm4
    ret
.quad2:
    xorps   xmm3, [rel sinf32_sign_mask]
    movaps  xmm0, xmm3
    ret

.return_nan:
    mov     eax, [rel sinf32_nan_bits]
    movd    xmm0, eax
    ret

; -----------------------------------------------------------------------------
; umath_sin_f32_array - sin(x) for an array of floats
; args:    rdi = destination pointer (dst)
;          rsi = source pointer (src)
;          rdx = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_sin_f32_array
umath_sin_f32_array:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done
    test    rdx, rdx
    jz      .done

.loop:
    movss   xmm0, [rsi]
    call    umath_sin_f32
    movss   [rdi], xmm0
    add     rsi, 4
    add     rdi, 4
    dec     rdx
    jnz     .loop

.done:
    ret

; -----------------------------------------------------------------------------
; umath_sin_f32_inplace - sin(x) in place for a float array
; args:    rdi = buffer pointer (buf)
;          rsi = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_sin_f32_inplace
umath_sin_f32_inplace:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done

.loop:
    movss   xmm0, [rdi]
    call    umath_sin_f32
    movss   [rdi], xmm0
    add     rdi, 4
    dec     rsi
    jnz     .loop

.done:
    ret

%endif ; GUARD_LIB_UMATH_MATH_FN_SIN_F32_ASM
