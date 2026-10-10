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
; Domain: pi/2 is split into three parts (21 + 21 + 53 significant bits),
; so n*p1 and n*p2 are exact while n < 2^32, i.e. |x| < 2^32 * pi/2 =~ 6.7e9.
; Measured against a 60-digit reference: max absolute error 1.1e-16 for
; |x| <= 6.5e9 (sin and cos). Beyond that the simple (not Payne-Hanek)
; reduction degrades roughly as |x| * 1e-16 (2e-6 by |x| = 2e10, 6e-5 by
; 1e12), and for |x| >= 2^52, where it is meaningless, the result is NaN.
; sin(x) = x for |x| < 2^-27, which also keeps the sign of -0.0.
;
; sin(NaN) = NaN, sin(±Inf) = NaN (undefined), matching libm.
;
; The array/inplace paths run the same algorithm two lanes at a time through
; sinf64__core2 (shared with cos_f64.asm and tan_f64.asm), bit-identical to
; the scalar routine per element.
; =============================================================================

bits 64

%include "lib/umath/cpuid/fallback.asm"

section .rodata
align 16
sinf64_two_over_pi:  dq 0.6366197723675814
sinf64_pi2_p1:        dq 1.570796012878418      ; pi/2 split into 21 + 21 + 53 bits:
sinf64_pi2_p2:        dq 3.139164164167596e-07  ; n*p1 and n*p2 are exact for n < 2^32
sinf64_pi2_p3:        dq 6.223372171896613e-14  ; p3 = pi/2 - p1 - p2 to 53 bits
sinf64_nan_bits:      dq 0x7FF8000000000000
sinf64_limit:         dq 4503599627370496.0   ; 2^52: |x| at or above -> NaN (see header)
sinf64_tiny:          dq 7.450580596923828e-09   ; 2^-27: below it sin(x) rounds to x

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

; two-lane copies for the packed paths (16-byte aligned memory operands)
align 16
sinf64_p_two_over_pi: dq 0.6366197723675814, 0.6366197723675814
sinf64_p_p1: dq 1.570796012878418, 1.570796012878418
sinf64_p_p2: dq 3.139164164167596e-07, 3.139164164167596e-07
sinf64_p_p3: dq 6.223372171896613e-14, 6.223372171896613e-14
sinf64_p_limit: dq 4503599627370496.0, 4503599627370496.0
sinf64_p_tiny: dq 7.450580596923828e-09, 7.450580596923828e-09
sinf64_p_one: dq 1.0, 1.0
sinf64_p_two: dq 2.0, 2.0
sinf64_p_three: dq 3.0, 3.0
sinf64_p_quarter: dq 0.25, 0.25
sinf64_p_four: dq 4.0, 4.0
sinf64_p_sc1: dq -0.16666666666666666, -0.16666666666666666
sinf64_p_sc2: dq 0.008333333333333333, 0.008333333333333333
sinf64_p_sc3: dq -0.0001984126984126984, -0.0001984126984126984
sinf64_p_sc4: dq 2.7557319223985893e-06, 2.7557319223985893e-06
sinf64_p_sc5: dq -2.505210838544172e-08, -2.505210838544172e-08
sinf64_p_sc6: dq 1.6059043836821613e-10, 1.6059043836821613e-10
sinf64_p_sc7: dq -7.647163731819816e-13, -7.647163731819816e-13
sinf64_p_sc8: dq 2.8114572543455206e-15, 2.8114572543455206e-15
sinf64_p_sc9: dq -8.22063524662433e-18, -8.22063524662433e-18
sinf64_p_cc1: dq -0.5, -0.5
sinf64_p_cc2: dq 0.041666666666666664, 0.041666666666666664
sinf64_p_cc3: dq -0.001388888888888889, -0.001388888888888889
sinf64_p_cc4: dq 2.48015873015873e-05, 2.48015873015873e-05
sinf64_p_cc5: dq -2.755731922398589e-07, -2.755731922398589e-07
sinf64_p_cc6: dq 2.08767569878681e-09, 2.08767569878681e-09
sinf64_p_cc7: dq -1.1470745597729725e-11, -1.1470745597729725e-11
sinf64_p_cc8: dq 4.779477332387385e-14, 4.779477332387385e-14
sinf64_p_cc9: dq -1.5619206968586225e-16, -1.5619206968586225e-16
sinf64_p_abs: dq 0x7FFFFFFFFFFFFFFF, 0x7FFFFFFFFFFFFFFF
sinf64_p_nan: dq 0x7FF8000000000000, 0x7FF8000000000000

section .text

; -----------------------------------------------------------------------------
; umath_sin_f64 - scalar double-precision sine
; args:    xmm0 = input value (x), radians
; returns: xmm0 = sin(x); NaN for NaN, +/-Inf or |x| >= 2^52
; -----------------------------------------------------------------------------
global umath_sin_f64
umath_sin_f64:
    ucomisd xmm0, xmm0
    jp      .return_nan           ; x is NaN

    movq    rax, xmm0
    mov     r8, 0x7FFFFFFFFFFFFFFF
    and     rax, r8
    movq    xmm6, rax              ; xmm6 = |x|
    ucomisd xmm6, [rel sinf64_limit]
    jae     .return_nan            ; |x| == Inf (sin(Inf) is undefined), or too
                                   ; large for this reduction (see header)
    ucomisd xmm6, [rel sinf64_tiny]
    jb      .return_x              ; sin(x) == x here; also keeps the sign of -0.0

    movsd   xmm1, [rel sinf64_two_over_pi]
    mulsd   xmm1, xmm0
    um_roundsd xmm1, xmm1, 0          ; xmm1 = n (round to nearest)

    movsd   xmm2, xmm1
    mulsd   xmm2, [rel sinf64_pi2_p1]
    subsd   xmm0, xmm2             ; exact (Sterbenz): x and n*p1 are close
    movsd   xmm2, xmm1
    mulsd   xmm2, [rel sinf64_pi2_p2]
    subsd   xmm0, xmm2
    movsd   xmm2, xmm1
    mulsd   xmm2, [rel sinf64_pi2_p3]
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

    cvttsd2si rax, xmm1             ; n is integral; 64-bit so n >= 2^31 keeps its low bits
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

.return_x:
    ret

.return_nan:
    mov     rax, [rel sinf64_nan_bits]
    movq    xmm0, rax
    ret

; -----------------------------------------------------------------------------
; sinf64_blend - lanes of %1 where mask %2 is set take %3 (register or memory)
; args:    %1 = values (in/out), %2 = mask (clobbered), %3 = source, %4 = scratch
; -----------------------------------------------------------------------------
%macro sinf64_blend 4
    movapd  %4, %3
    andpd   %4, %2
    andnpd  %2, %1
    orpd    %2, %4
    movapd  %1, %2
%endmacro

; -----------------------------------------------------------------------------
; sinf64__core2 - internal: shared packed reduction for sin/cos/tan, two lanes
; args:    xmm0 = two input values
; returns: xmm3 = sin(r), xmm4 = cos(r), xmm1 = quadrant n mod 4 (0..3, as
;          double), xmm8 = |x|, xmm9 = x
; Same operations in the same order as umath_sin_f64/umath_cos_f64; the
; quadrant is n - 4*floor(n/4) computed exactly, which equals the scalar's
; (cvttsd2si n) & 3 for negative n too. Clobbers xmm0-xmm9, no GPRs.
; Not declared global (cos_f64.asm and tan_f64.asm call it).
; -----------------------------------------------------------------------------
sinf64__core2:
    movapd  xmm9, xmm0
    movapd  xmm8, xmm0
    andpd   xmm8, [rel sinf64_p_abs]

    movapd  xmm1, [rel sinf64_p_two_over_pi]
    mulpd   xmm1, xmm0
    um_roundpd xmm1, xmm1, 0       ; n (round to nearest)

    movapd  xmm2, xmm1
    mulpd   xmm2, [rel sinf64_p_p1]
    subpd   xmm0, xmm2
    movapd  xmm2, xmm1
    mulpd   xmm2, [rel sinf64_p_p2]
    subpd   xmm0, xmm2
    movapd  xmm2, xmm1
    mulpd   xmm2, [rel sinf64_p_p3]
    subpd   xmm0, xmm2          ; r

    movapd  xmm2, xmm0
    mulpd   xmm2, xmm0          ; r^2

    movapd  xmm3, [rel sinf64_p_sc9]
    mulpd   xmm3, xmm2
    addpd   xmm3, [rel sinf64_p_sc8]
    mulpd   xmm3, xmm2
    addpd   xmm3, [rel sinf64_p_sc7]
    mulpd   xmm3, xmm2
    addpd   xmm3, [rel sinf64_p_sc6]
    mulpd   xmm3, xmm2
    addpd   xmm3, [rel sinf64_p_sc5]
    mulpd   xmm3, xmm2
    addpd   xmm3, [rel sinf64_p_sc4]
    mulpd   xmm3, xmm2
    addpd   xmm3, [rel sinf64_p_sc3]
    mulpd   xmm3, xmm2
    addpd   xmm3, [rel sinf64_p_sc2]
    mulpd   xmm3, xmm2
    addpd   xmm3, [rel sinf64_p_sc1]
    mulpd   xmm3, xmm2
    addpd   xmm3, [rel sinf64_p_one]
    mulpd   xmm3, xmm0
    movapd  xmm4, [rel sinf64_p_cc9]
    mulpd   xmm4, xmm2
    addpd   xmm4, [rel sinf64_p_cc8]
    mulpd   xmm4, xmm2
    addpd   xmm4, [rel sinf64_p_cc7]
    mulpd   xmm4, xmm2
    addpd   xmm4, [rel sinf64_p_cc6]
    mulpd   xmm4, xmm2
    addpd   xmm4, [rel sinf64_p_cc5]
    mulpd   xmm4, xmm2
    addpd   xmm4, [rel sinf64_p_cc4]
    mulpd   xmm4, xmm2
    addpd   xmm4, [rel sinf64_p_cc3]
    mulpd   xmm4, xmm2
    addpd   xmm4, [rel sinf64_p_cc2]
    mulpd   xmm4, xmm2
    addpd   xmm4, [rel sinf64_p_cc1]
    mulpd   xmm4, xmm2
    addpd   xmm4, [rel sinf64_p_one]

    movapd  xmm5, xmm1
    mulpd   xmm5, [rel sinf64_p_quarter]
    um_roundpd xmm5, xmm5, 1       ; floor(n / 4)
    mulpd   xmm5, [rel sinf64_p_four]
    subpd   xmm1, xmm5          ; n mod 4, exact
    ret

; -----------------------------------------------------------------------------
; sinf64__packed2 - internal: sin(x) of 2 lanes, bit-identical to
;                   umath_sin_f64 per lane
; args:    xmm0 = input values
; returns: xmm0 = results
; Clobbers xmm1-xmm9, no GPRs. Not declared global.
; -----------------------------------------------------------------------------
sinf64__packed2:
    call    sinf64__core2
    jmp     sinf64__select_sin

; -----------------------------------------------------------------------------
; sinf64__select_sin - internal: sin(x) from the sinf64__core2 outputs
; args:    xmm1, xmm3, xmm4, xmm8, xmm9 as left by sinf64__core2 (preserved)
; returns: xmm0 = sin(x), bit-identical to umath_sin_f64
; Clobbers xmm5-xmm6, no GPRs. Not declared global.
; -----------------------------------------------------------------------------
sinf64__select_sin:
    movapd  xmm0, xmm3
    ; quadrant table: 0: s, 1: c, 2: -s, 3: -c
    movapd  xmm5, xmm1
    cmpeqpd xmm5, [rel sinf64_p_one]
    movapd  xmm6, xmm1
    cmpeqpd xmm6, [rel sinf64_p_three]
    orpd    xmm5, xmm6          ; odd quadrant: the other polynomial
    sinf64_blend xmm0, xmm5, xmm4, xmm6
    movapd  xmm5, xmm1
    cmpnltpd xmm5, [rel sinf64_p_two]    ; quadrants 2 and 3: negate
    andpd   xmm5, [rel sinf64_sign_mask]
    xorpd   xmm0, xmm5
    movapd  xmm5, xmm8
    cmpltpd xmm5, [rel sinf64_p_tiny]
    sinf64_blend xmm0, xmm5, xmm9, xmm6      ; tiny |x|: x itself (keeps -0.0)
    movapd  xmm5, xmm8
    cmpnltpd xmm5, [rel sinf64_p_limit]      ; |x| >= 2^52, Inf, or NaN
    sinf64_blend xmm0, xmm5, [rel sinf64_p_nan], xmm6
    ret

; -----------------------------------------------------------------------------
; sinf64__select_cos - internal: cos(x) from the sinf64__core2 outputs
; args:    xmm1, xmm3, xmm4, xmm8, xmm9 as left by sinf64__core2 (preserved)
; returns: xmm0 = cos(x), bit-identical to umath_cos_f64
; Clobbers xmm5-xmm6, no GPRs. Not declared global.
; -----------------------------------------------------------------------------
sinf64__select_cos:
    movapd  xmm0, xmm4
    ; quadrant table: 0: c, 1: -s, 2: -c, 3: s
    movapd  xmm5, xmm1
    cmpeqpd xmm5, [rel sinf64_p_one]
    movapd  xmm6, xmm1
    cmpeqpd xmm6, [rel sinf64_p_three]
    orpd    xmm5, xmm6          ; odd quadrant: the other polynomial
    sinf64_blend xmm0, xmm5, xmm3, xmm6
    movapd  xmm5, xmm1
    cmpeqpd xmm5, [rel sinf64_p_one]
    movapd  xmm6, xmm1
    cmpeqpd xmm6, [rel sinf64_p_two]
    orpd    xmm5, xmm6          ; quadrants 1 and 2: negate
    andpd   xmm5, [rel sinf64_sign_mask]
    xorpd   xmm0, xmm5
    movapd  xmm5, xmm8
    cmpnltpd xmm5, [rel sinf64_p_limit]      ; |x| >= 2^52, Inf, or NaN
    sinf64_blend xmm0, xmm5, [rel sinf64_p_nan], xmm6
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

    mov     rcx, rdx
    shr     rcx, 1              ; count of 2-double groups
    jz      .tail
.loop:
    movupd  xmm0, [rsi]
    call    sinf64__packed2  ; preserves rcx (no GPRs used)
    movupd  [rdi], xmm0
    add     rsi, 16
    add     rdi, 16
    dec     rcx
    jnz     .loop
.tail:
    and     rdx, 1
    jz      .done
.tail_loop:
    movsd   xmm0, [rsi]
    call    umath_sin_f64
    movsd   [rdi], xmm0
    add     rsi, 8
    add     rdi, 8
    dec     rdx
    jnz     .tail_loop
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

    mov     rcx, rsi
    shr     rcx, 1
    jz      .tail
.loop:
    movupd  xmm0, [rdi]
    call    sinf64__packed2
    movupd  [rdi], xmm0
    add     rdi, 16
    dec     rcx
    jnz     .loop
.tail:
    and     rsi, 1
    jz      .done
.tail_loop:
    movsd   xmm0, [rdi]
    call    umath_sin_f64
    movsd   [rdi], xmm0
    add     rdi, 8
    dec     rsi
    jnz     .tail_loop
.done:
    ret

%endif ; GUARD_LIB_UMATH_MATH_FN_SIN_F64_ASM
