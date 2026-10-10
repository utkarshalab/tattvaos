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
;   2. r = x - n*p1 - n*p2 - n*p3        ; reduced argument, |r| <= pi/4,
;      pi/2 split into three parts (21 + 21 + 53 significant bits) so the
;      n*p1 and n*p2 products are exact
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
; the split of pi/2 only keeps n*p1 exact if p1 itself hasn't
; already lost precision to being stored as a single float, and a first
; version of this file that did the whole reduction in float32 was
; measurably wrong (~1.7e-5 absolute error) by x=1000 — not some
; pathological extreme, just because n grows large enough that a
; float32-rounded hi's exactness guarantee had already broken down. This
; is the same fix real sinf/cosf implementations use, not an original
; technique.
;
; Domain: still a simple (not Payne-Hanek) range reduction: accurate for
; |x| < 2^32 * pi/2 =~ 6.7e9, degrading beyond it, NaN for |x| >= 2^52
; (see sin_f64.asm's header for the measured numbers). sin(x) = x for
; |x| < 2^-12, which also keeps the sign of -0.0.
;
; sin(NaN) = NaN, sin(±Inf) = NaN (undefined), matching libm.
; =============================================================================

bits 64

section .rodata
align 16
sinf32_two_over_pi_d:  dq 0.6366197723675814
sinf32_pi2_p1_d:        dq 1.570796012878418      ; pi/2 split into 21 + 21 + 53 bits:
sinf32_pi2_p2_d:        dq 3.139164164167596e-07  ; n*p1 and n*p2 are exact for n < 2^32
sinf32_pi2_p3_d:        dq 6.223372171896613e-14  ; p3 = pi/2 - p1 - p2 to 53 bits
sinf32_nan_bits:      dd 0x7FC00000
sinf32_limit:         dd 4503599627370496.0   ; 2^52: |x| at or above -> NaN (see header)
sinf32_tiny:          dd 0.000244140625   ; 2^-12: below it sin(x) rounds to x

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

; packed copies for the array paths (16-byte aligned memory operands)
align 16
sinf32_p_two_over_pi_d: dq 0.6366197723675814, 0.6366197723675814
sinf32_p_p1_d: dq 1.570796012878418, 1.570796012878418
sinf32_p_p2_d: dq 3.139164164167596e-07, 3.139164164167596e-07
sinf32_p_p3_d: dq 6.223372171896613e-14, 6.223372171896613e-14
sinf32_p_quarter_d: dq 0.25, 0.25
sinf32_p_four_d: dq 4.0, 4.0
sinf32_p_limit: times 4 dd 4503599627370496.0
sinf32_p_tiny: times 4 dd 0.000244140625
sinf32_p_one: times 4 dd 1.0
sinf32_p_two: times 4 dd 2.0
sinf32_p_three: times 4 dd 3.0
sinf32_p_sc1: times 4 dd -0.16666666666666666
sinf32_p_sc2: times 4 dd 0.008333333333333333
sinf32_p_sc3: times 4 dd -0.0001984126984126984
sinf32_p_sc4: times 4 dd 2.7557319223985893e-06
sinf32_p_sc5: times 4 dd -2.505210838544172e-08
sinf32_p_cc1: times 4 dd -0.5
sinf32_p_cc2: times 4 dd 0.041666666666666664
sinf32_p_cc3: times 4 dd -0.001388888888888889
sinf32_p_cc4: times 4 dd 2.48015873015873e-05
sinf32_p_cc5: times 4 dd -2.755731922398589e-07
sinf32_p_abs: times 4 dd 0x7FFFFFFF
sinf32_p_nan: times 4 dd 0x7FC00000

section .text

; -----------------------------------------------------------------------------
; umath_sin_f32 - scalar single-precision sine
; args:    xmm0 = input value (x), radians
; returns: xmm0 = sin(x); NaN for NaN, +/-Inf or |x| >= 2^52
; -----------------------------------------------------------------------------
global umath_sin_f32
umath_sin_f32:
    ucomiss xmm0, xmm0
    jp      .return_nan           ; x is NaN

    movd    eax, xmm0
    and     eax, 0x7FFFFFFF
    movd    xmm6, eax              ; xmm6 = |x|
    ucomiss xmm6, [rel sinf32_limit]
    jae     .return_nan            ; |x| == Inf (sin(Inf) is undefined), or too
                                   ; large for this reduction (see header)
    ucomiss xmm6, [rel sinf32_tiny]
    jb      .return_x              ; sin(x) == x here; also keeps the sign of -0.0

    cvtss2sd xmm0, xmm0             ; widen x to double for the reduction

    movsd   xmm1, [rel sinf32_two_over_pi_d]
    mulsd   xmm1, xmm0
    roundsd xmm1, xmm1, 0          ; xmm1 = n (double, round to nearest)

    movsd   xmm2, xmm1
    mulsd   xmm2, [rel sinf32_pi2_p1_d]
    subsd   xmm0, xmm2             ; exact (Sterbenz): x and n*p1 are close
    movsd   xmm2, xmm1
    mulsd   xmm2, [rel sinf32_pi2_p2_d]
    subsd   xmm0, xmm2
    movsd   xmm2, xmm1
    mulsd   xmm2, [rel sinf32_pi2_p3_d]
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

    cvttsd2si rax, xmm1             ; n is integral; 64-bit so n >= 2^31 keeps its low bits
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

.return_x:
    ret

.return_nan:
    mov     eax, [rel sinf32_nan_bits]
    movd    xmm0, eax
    ret

; -----------------------------------------------------------------------------
; sinf32_blend - lanes of %1 where mask %2 is set take %3 (register or memory)
; args:    %1 = values (in/out), %2 = mask (clobbered), %3 = source, %4 = scratch
; -----------------------------------------------------------------------------
%macro sinf32_blend 4
    movaps  %4, %3
    andps   %4, %2
    andnps  %2, %1
    orps    %2, %4
    movaps  %1, %2
%endmacro

; -----------------------------------------------------------------------------
; sinf32__core4 - internal: shared packed reduction for sin/cos/tan, four lanes
; args:    xmm0 = four input floats
; returns: xmm3 = sin(r), xmm4 = cos(r), xmm1 = quadrant n mod 4 (0..3, as
;          float), xmm8 = |x|, xmm9 = x
; As in umath_sin_f32: each pair of lanes is widened to double, reduced in
; double, and r narrowed to float before the float polynomials. The quadrant
; is n - 4*floor(n/4) in double (exact). Clobbers xmm0-xmm13, no GPRs.
; Not declared global (cos_f32.asm and tan_f32.asm call it).
; -----------------------------------------------------------------------------
sinf32__core4:
    movaps  xmm9, xmm0
    movaps  xmm8, xmm0
    andps   xmm8, [rel sinf32_p_abs]

    cvtps2pd xmm10, xmm0        ; lanes 0-1 widened
    movhlps xmm11, xmm0
    cvtps2pd xmm11, xmm11       ; lanes 2-3 widened
    movapd  xmm1, [rel sinf32_p_two_over_pi_d]
    mulpd   xmm1, xmm10
    roundpd xmm1, xmm1, 0         ; n
    movapd  xmm2, xmm10
    movapd  xmm4, xmm1
    mulpd   xmm4, [rel sinf32_p_p1_d]
    subpd   xmm2, xmm4
    movapd  xmm4, xmm1
    mulpd   xmm4, [rel sinf32_p_p2_d]
    subpd   xmm2, xmm4
    movapd  xmm4, xmm1
    mulpd   xmm4, [rel sinf32_p_p3_d]
    subpd   xmm2, xmm4          ; r (double)
    movapd  xmm3, xmm1
    mulpd   xmm3, [rel sinf32_p_quarter_d]
    roundpd xmm3, xmm3, 1         ; floor(n / 4)
    mulpd   xmm3, [rel sinf32_p_four_d]
    subpd   xmm1, xmm3            ; n mod 4, exact
    movapd  xmm12, [rel sinf32_p_two_over_pi_d]
    mulpd   xmm12, xmm11
    roundpd xmm12, xmm12, 0         ; n
    movapd  xmm13, xmm11
    movapd  xmm4, xmm12
    mulpd   xmm4, [rel sinf32_p_p1_d]
    subpd   xmm13, xmm4
    movapd  xmm4, xmm12
    mulpd   xmm4, [rel sinf32_p_p2_d]
    subpd   xmm13, xmm4
    movapd  xmm4, xmm12
    mulpd   xmm4, [rel sinf32_p_p3_d]
    subpd   xmm13, xmm4          ; r (double)
    movapd  xmm5, xmm12
    mulpd   xmm5, [rel sinf32_p_quarter_d]
    roundpd xmm5, xmm5, 1         ; floor(n / 4)
    mulpd   xmm5, [rel sinf32_p_four_d]
    subpd   xmm12, xmm5            ; n mod 4, exact
    cvtpd2ps xmm0, xmm2         ; r lanes 0-1, narrowed to float
    cvtpd2ps xmm13, xmm13       ; r lanes 2-3
    movlhps xmm0, xmm13         ; r (float)
    cvtpd2ps xmm1, xmm1         ; quadrant lanes 0-1 (exact: 0..3)
    cvtpd2ps xmm12, xmm12
    movlhps xmm1, xmm12         ; quadrant (float)

    movaps  xmm2, xmm0
    mulps   xmm2, xmm0          ; r^2

    movaps  xmm3, [rel sinf32_p_sc5]
    mulps   xmm3, xmm2
    addps   xmm3, [rel sinf32_p_sc4]
    mulps   xmm3, xmm2
    addps   xmm3, [rel sinf32_p_sc3]
    mulps   xmm3, xmm2
    addps   xmm3, [rel sinf32_p_sc2]
    mulps   xmm3, xmm2
    addps   xmm3, [rel sinf32_p_sc1]
    mulps   xmm3, xmm2
    addps   xmm3, [rel sinf32_p_one]
    mulps   xmm3, xmm0
    movaps  xmm4, [rel sinf32_p_cc5]
    mulps   xmm4, xmm2
    addps   xmm4, [rel sinf32_p_cc4]
    mulps   xmm4, xmm2
    addps   xmm4, [rel sinf32_p_cc3]
    mulps   xmm4, xmm2
    addps   xmm4, [rel sinf32_p_cc2]
    mulps   xmm4, xmm2
    addps   xmm4, [rel sinf32_p_cc1]
    mulps   xmm4, xmm2
    addps   xmm4, [rel sinf32_p_one]
    ret

; -----------------------------------------------------------------------------
; sinf32__packed4 - internal: sin(x) of 4 lanes, bit-identical to
;                   umath_sin_f32 per lane
; args:    xmm0 = input values
; returns: xmm0 = results
; Clobbers xmm1-xmm13, no GPRs. Not declared global.
; -----------------------------------------------------------------------------
sinf32__packed4:
    call    sinf32__core4
    jmp     sinf32__select_sin

; -----------------------------------------------------------------------------
; sinf32__select_sin - internal: sin(x) from the sinf32__core4 outputs
; args:    xmm1, xmm3, xmm4, xmm8, xmm9 as left by sinf32__core4 (preserved)
; returns: xmm0 = sin(x), bit-identical to umath_sin_f32
; Clobbers xmm5-xmm6, no GPRs. Not declared global.
; -----------------------------------------------------------------------------
sinf32__select_sin:
    movaps  xmm0, xmm3
    ; quadrant table: 0: s, 1: c, 2: -s, 3: -c
    movaps  xmm5, xmm1
    cmpeqps xmm5, [rel sinf32_p_one]
    movaps  xmm6, xmm1
    cmpeqps xmm6, [rel sinf32_p_three]
    orps    xmm5, xmm6          ; odd quadrant: the other polynomial
    sinf32_blend xmm0, xmm5, xmm4, xmm6
    movaps  xmm5, xmm1
    cmpnltps xmm5, [rel sinf32_p_two]    ; quadrants 2 and 3: negate
    andps   xmm5, [rel sinf32_sign_mask]
    xorps   xmm0, xmm5
    movaps  xmm5, xmm8
    cmpltps xmm5, [rel sinf32_p_tiny]
    sinf32_blend xmm0, xmm5, xmm9, xmm6      ; tiny |x|: x itself (keeps -0.0)
    movaps  xmm5, xmm8
    cmpnltps xmm5, [rel sinf32_p_limit]      ; |x| >= 2^52, Inf, or NaN
    sinf32_blend xmm0, xmm5, [rel sinf32_p_nan], xmm6
    ret

; -----------------------------------------------------------------------------
; sinf32__select_cos - internal: cos(x) from the sinf32__core4 outputs
; args:    xmm1, xmm3, xmm4, xmm8, xmm9 as left by sinf32__core4 (preserved)
; returns: xmm0 = cos(x), bit-identical to umath_cos_f32
; Clobbers xmm5-xmm6, no GPRs. Not declared global.
; -----------------------------------------------------------------------------
sinf32__select_cos:
    movaps  xmm0, xmm4
    ; quadrant table: 0: c, 1: -s, 2: -c, 3: s
    movaps  xmm5, xmm1
    cmpeqps xmm5, [rel sinf32_p_one]
    movaps  xmm6, xmm1
    cmpeqps xmm6, [rel sinf32_p_three]
    orps    xmm5, xmm6          ; odd quadrant: the other polynomial
    sinf32_blend xmm0, xmm5, xmm3, xmm6
    movaps  xmm5, xmm1
    cmpeqps xmm5, [rel sinf32_p_one]
    movaps  xmm6, xmm1
    cmpeqps xmm6, [rel sinf32_p_two]
    orps    xmm5, xmm6          ; quadrants 1 and 2: negate
    andps   xmm5, [rel sinf32_sign_mask]
    xorps   xmm0, xmm5
    movaps  xmm5, xmm8
    cmpnltps xmm5, [rel sinf32_p_limit]      ; |x| >= 2^52, Inf, or NaN
    sinf32_blend xmm0, xmm5, [rel sinf32_p_nan], xmm6
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

    mov     rcx, rdx
    shr     rcx, 2              ; count of 4-float groups
    jz      .tail
.loop:
    movups  xmm0, [rsi]
    call    sinf32__packed4  ; preserves rcx (no GPRs used)
    movups  [rdi], xmm0
    add     rsi, 16
    add     rdi, 16
    dec     rcx
    jnz     .loop
.tail:
    and     rdx, 3
    jz      .done
.tail_loop:
    movss   xmm0, [rsi]
    call    umath_sin_f32
    movss   [rdi], xmm0
    add     rsi, 4
    add     rdi, 4
    dec     rdx
    jnz     .tail_loop
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

    mov     rcx, rsi
    shr     rcx, 2
    jz      .tail
.loop:
    movups  xmm0, [rdi]
    call    sinf32__packed4
    movups  [rdi], xmm0
    add     rdi, 16
    dec     rcx
    jnz     .loop
.tail:
    and     rsi, 3
    jz      .done
.tail_loop:
    movss   xmm0, [rdi]
    call    umath_sin_f32
    movss   [rdi], xmm0
    add     rdi, 4
    dec     rsi
    jnz     .tail_loop
.done:
    ret

%endif ; GUARD_LIB_UMATH_MATH_FN_SIN_F32_ASM
