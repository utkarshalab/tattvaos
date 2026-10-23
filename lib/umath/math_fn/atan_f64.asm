%ifndef GUARD_LIB_UMATH_MATH_FN_ATAN_F64_ASM
%define GUARD_LIB_UMATH_MATH_FN_ATAN_F64_ASM
; =============================================================================
; umath - unified math library
; math_fn/atan_f64.asm - double-precision arctangent
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; atan(-x) = -atan(x), so the core works on a = |x|:
;
;   1. Fold: a > 1 uses atan(a) = pi/2 - atan(1/a), so a is in [0, 1].
;   2. Shift: pick the anchor T in {0, tan(pi/12), tan(pi/6), 1} nearest a
;      (breakpoints tan(pi/24), tan(3pi/24), tan(5pi/24)) and use
;          atan(a) = atan(T) + atan(t),  t = (a - T) / (1 + a*T),
;      which leaves |t| <= tan(pi/24) = 0.1317.
;   3. atan(t) = t + t^3 * q(t^2), the alternating series up to t^19:
;      t^(2n)/(2n+1) drops below 2^-56 from n = 9 on this range.
;   4. Reconstruct as H + (L + atan(t)), H + L being atan(T) -- or
;      pi/2 - atan(T) with atan(t) negated when folded -- as a hi/lo pair.
;      The pairs are computed from the double T actually stored, so the
;      identity in step 2 holds exactly for it.
;
; For the unfolded first interval H = L = 0, so tiny x come back exactly
; (atan(x) = x to double precision below ~1.5e-8). +-Inf gives +-pi/2, NaN
; propagates (quieted).
;
; atanf64__core (internal) is shared with atan2, asin and acos.
; =============================================================================

bits 64

%include "lib/umath/math_fn/loops.asm"

section .rodata
align 8
atanf64_one:        dq 1.0
atanf64_b1:         dq 0x3FC0D9FD31C98BF9       ; tan(pi/24)
atanf64_b2:         dq 0x3FDA827999FCEF32       ; tan(3pi/24)
atanf64_b3:         dq 0x3FE88DF153D6A676       ; tan(5pi/24)
atanf64_anchor:                                 ; T_k
    dq 0x0000000000000000, 0x3FD126145E9ECD56, 0x3FE279A74590331C, 0x3FF0000000000000
atanf64_hi:                                     ; atan(T_k), then pi/2 - atan(T_k)
    dq 0x0000000000000000, 0x3FD0C152382D7365, 0x3FE0C152382D7365, 0x3FE921FB54442D18
    dq 0x3FF921FB54442D18, 0x3FF4F1A6C638D03F, 0x3FF0C152382D7366, 0x3FE921FB54442D18
atanf64_lo:
    dq 0x0000000000000000, 0x3C759EC2C5C86603, 0x3C82A323E45D5C68, 0x3C81A62633145C07
    dq 0x3C91A62633145C07, 0xBC6E0C53F2EDEBCF, 0xBC97AB6BBF1A522D, 0x3C81A62633145C07
; (-1)^n / (2n+1), n = 1 .. 9
atanf64_c3:         dq -0.3333333333333333
atanf64_c5:         dq 0.2
atanf64_c7:         dq -0.14285714285714285
atanf64_c9:         dq 0.1111111111111111
atanf64_c11:        dq -0.09090909090909091
atanf64_c13:        dq 0.07692307692307693
atanf64_c15:        dq -0.06666666666666667
atanf64_c17:        dq 0.058823529411764705
atanf64_c19:        dq -0.05263157894736842
align 16                                        ; xorpd memory operand
atanf64_sign:       dq 0x8000000000000000, 0x8000000000000000

section .text

; -----------------------------------------------------------------------------
; atanf64__core - internal: atan(a) for a >= 0 (a may be +Inf)
; args:    xmm0 = a
; returns: xmm0 = atan(a), in [0, pi/2]
; Clobbers rax, rcx, rdx, xmm1-xmm4. Makes no calls.
; -----------------------------------------------------------------------------
atanf64__core:
    xor     eax, eax            ; 1 when folded
    comisd  xmm0, [rel atanf64_one]
    jbe     .unfolded
    movsd   xmm1, [rel atanf64_one]
    divsd   xmm1, xmm0          ; 1/a (+Inf -> 0)
    movapd  xmm0, xmm1
    mov     eax, 4              ; row offset of the pi/2 - atan(T) pairs
.unfolded:
    xor     ecx, ecx
    comisd  xmm0, [rel atanf64_b1]
    jbe     .anchor
    inc     ecx
    comisd  xmm0, [rel atanf64_b2]
    jbe     .anchor
    inc     ecx
    comisd  xmm0, [rel atanf64_b3]
    jbe     .anchor
    inc     ecx
.anchor:
    lea     rdx, [rel atanf64_anchor]
    movsd   xmm2, [rdx + rcx*8] ; T
    movapd  xmm1, xmm0
    subsd   xmm1, xmm2          ; a - T
    mulsd   xmm2, xmm0
    addsd   xmm2, [rel atanf64_one]  ; 1 + a*T
    divsd   xmm1, xmm2          ; t
    movapd  xmm2, xmm1
    mulsd   xmm2, xmm1          ; t^2
    movsd   xmm3, [rel atanf64_c19]
    mulsd   xmm3, xmm2
    addsd   xmm3, [rel atanf64_c17]
    mulsd   xmm3, xmm2
    addsd   xmm3, [rel atanf64_c15]
    mulsd   xmm3, xmm2
    addsd   xmm3, [rel atanf64_c13]
    mulsd   xmm3, xmm2
    addsd   xmm3, [rel atanf64_c11]
    mulsd   xmm3, xmm2
    addsd   xmm3, [rel atanf64_c9]
    mulsd   xmm3, xmm2
    addsd   xmm3, [rel atanf64_c7]
    mulsd   xmm3, xmm2
    addsd   xmm3, [rel atanf64_c5]
    mulsd   xmm3, xmm2
    addsd   xmm3, [rel atanf64_c3]  ; q(t^2)
    mulsd   xmm2, xmm1          ; t^3
    mulsd   xmm3, xmm2
    addsd   xmm1, xmm3          ; atan(t) = t + t^3 q
    test    eax, eax
    jz      .combine
    xorpd   xmm1, [rel atanf64_sign]  ; folded: pi/2 - atan(T) - atan(t)
.combine:
    add     ecx, eax
    lea     rdx, [rel atanf64_lo]
    addsd   xmm1, [rdx + rcx*8]
    lea     rdx, [rel atanf64_hi]
    movsd   xmm0, [rdx + rcx*8]
    addsd   xmm0, xmm1
    ret

; -----------------------------------------------------------------------------
; umath_atan_f64 - scalar arctangent
; args:    xmm0 = x
; returns: xmm0 = atan(x), in [-pi/2, pi/2]
; -----------------------------------------------------------------------------
global umath_atan_f64
umath_atan_f64:
    ucomisd xmm0, xmm0
    jp      .nan
    movq    rax, xmm0
    mov     r8, rax
    btr     rax, 63
    xor     r8, rax             ; sign bit of x
    movq    xmm0, rax
    call    atanf64__core
    movq    rax, xmm0
    or      rax, r8
    movq    xmm0, rax
    ret
.nan:
    addsd   xmm0, xmm0
    ret

mathfn_unary_arrays umath_atan_f64, umath_atan_f64, 8

%endif ; GUARD_LIB_UMATH_MATH_FN_ATAN_F64_ASM
