%ifndef GUARD_LIB_UMATH_MATH_FN_CBRT_F64_ASM
%define GUARD_LIB_UMATH_MATH_FN_CBRT_F64_ASM
; =============================================================================
; umath - unified math library
; math_fn/cbrt_f64.asm - double-precision cube root
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; cbrt(-x) = -cbrt(x), so work on a = |x|:
;
;   1. Exact reduction: a = a' * 2^(3q) with a' in [1, 8) (subnormal a is
;      first scaled by 2^54 = 2^(3*18)). Then cbrt(a) = cbrt(a') * 2^q, and
;      every intermediate below stays far from overflow and subnormals.
;   2. Seed: bits(y0) = bits(a')/3 + 0x2AA0000000000000 -- dividing the
;      biased pattern by 3 divides the exponent by 3, the constant restores
;      the bias (exact at a' = 1). The seed is within 5.9% of the root.
;   3. Four Newton steps y = (2y + a'/y^2) / 3: the relative error squares
;      each step (5.9e-2 -> 3.5e-3 -> 1.2e-5 -> 1.5e-10 -> 2e-20), so y is
;      limited only by the last step's own roundings (~2-3 ULP).
;   4. One correction from the exact residual: y^3 is formed as a sum of
;      exact products (Dekker's two-product, which needs no FMA), so
;      d = a' - y^3 is accurate to ~2^-100, and y + d/(3y^2) rounds once.
;      The result is within about half an ULP; perfect cubes come out exact.
;   5. Multiply by 2^q (exact: the root is normal) and reattach the sign.
;
; +-0, +-Inf and NaN return themselves (NaN quieted).
; =============================================================================

bits 64

%include "lib/umath/math_fn/loops.asm"

section .rodata
align 8
cbrtf64_dbl_min:    dq 2.2250738585072014e-308
cbrtf64_two_54:     dq 18014398509481984.0      ; 2^54
cbrtf64_three:      dq 3.0
cbrtf64_split:      dq 134217729.0              ; 2^27 + 1 (Dekker split)

section .text

; -----------------------------------------------------------------------------
; cbrtf64_two_prod - %1 * %2 = %3 + %4 exactly (Dekker, no FMA)
; args: %1, %2 = inputs (preserved), %3 = product, %4 = error;
;       %5-%8 = scratch registers
; -----------------------------------------------------------------------------
%macro cbrtf64_two_prod 8
    movapd  %3, %1
    mulsd   %3, %2              ; p = a*b
    ; split a -> %5 (hi), %6 (lo)
    movsd   %5, [rel cbrtf64_split]
    mulsd   %5, %1
    movapd  %6, %5
    subsd   %6, %1
    subsd   %5, %6              ; ah = c - (c - a)
    movapd  %6, %1
    subsd   %6, %5              ; al = a - ah
    ; split b -> %7 (hi), %8 (lo)
    movsd   %7, [rel cbrtf64_split]
    mulsd   %7, %2
    movapd  %8, %7
    subsd   %8, %2
    subsd   %7, %8              ; bh
    movapd  %8, %2
    subsd   %8, %7              ; bl
    ; e = ((ah*bh - p) + ah*bl + al*bh) + al*bl
    movapd  %4, %5
    mulsd   %4, %7
    subsd   %4, %3
    mulsd   %5, %8              ; ah*bl
    addsd   %4, %5
    mulsd   %7, %6              ; bh*al
    addsd   %4, %7
    mulsd   %6, %8              ; al*bl
    addsd   %4, %6
%endmacro

; -----------------------------------------------------------------------------
; umath_cbrt_f64 - scalar cube root
; args:    xmm0 = x
; returns: xmm0 = cbrt(x)
; -----------------------------------------------------------------------------
global umath_cbrt_f64
umath_cbrt_f64:
    movq    rax, xmm0
    mov     r8, rax
    btr     rax, 63             ; rax = bits of |x|
    mov     rcx, 0x7FF0000000000000
    cmp     rax, rcx
    jae     .special            ; Inf or NaN
    test    rax, rax
    jz      .special            ; +-0
    xor     r8, rax             ; r8 = sign bit alone
    xor     r9d, r9d            ; r9 = 18 when pre-scaled
    movq    xmm0, rax
    comisd  xmm0, [rel cbrtf64_dbl_min]
    jae     .reduce
    mulsd   xmm0, [rel cbrtf64_two_54]
    movq    rax, xmm0
    mov     r9d, 18
.reduce:
    ; e = unbiased exponent, q = floor(e / 3), r = e - 3q in {0, 1, 2}
    mov     rcx, rax
    shr     rcx, 52
    sub     ecx, 1023 - 1200    ; e + 1200 > 0, a multiple of 3 offset
    mov     eax, ecx
    xor     edx, edx
    mov     r10d, 3
    div     r10d                ; eax = (e + 1200) / 3, edx = r
    sub     eax, 400            ; q
    sub     eax, r9d            ; undo the 2^54 pre-scale: q - 18
    mov     r10d, eax           ; r10 = final exponent of the root
    movq    rax, xmm0
    mov     rcx, 0x000FFFFFFFFFFFFF
    and     rax, rcx
    lea     ecx, [rdx + 1023]
    shl     rcx, 52
    or      rax, rcx
    movq    xmm0, rax           ; a' in [1, 8)
    ; seed
    xor     edx, edx
    mov     ecx, 3
    div     rcx
    mov     rcx, 0x2AA0000000000000
    add     rax, rcx
    movq    xmm1, rax           ; y0
%rep 4
    movapd  xmm2, xmm1
    mulsd   xmm2, xmm1          ; y^2
    movapd  xmm3, xmm0
    divsd   xmm3, xmm2          ; a'/y^2
    addsd   xmm1, xmm1
    addsd   xmm1, xmm3
    divsd   xmm1, [rel cbrtf64_three]
%endrep
    ; d = a' - y^3 with y^3 = y*y*y formed exactly enough:
    ; y*y = p + pe; p*y = q + qe; y^3 = q + qe + pe*y
    cbrtf64_two_prod xmm1, xmm1, xmm2, xmm3, xmm4, xmm5, xmm6, xmm7  ; p, pe
    movapd  xmm8, xmm3
    mulsd   xmm8, xmm1          ; pe*y (tiny; its rounding is negligible)
    cbrtf64_two_prod xmm2, xmm1, xmm9, xmm10, xmm4, xmm5, xmm6, xmm7 ; q, qe
    movapd  xmm3, xmm0
    subsd   xmm3, xmm9          ; a' - q, exact (Sterbenz)
    subsd   xmm3, xmm10
    subsd   xmm3, xmm8          ; d
    mulsd   xmm2, [rel cbrtf64_three]  ; 3y^2 (approximately)
    divsd   xmm3, xmm2
    addsd   xmm1, xmm3          ; y + d/(3y^2), one rounding
    ; * 2^q and the sign
    lea     eax, [r10d + 1023]
    shl     rax, 52
    movq    xmm0, rax
    mulsd   xmm0, xmm1
    movq    rax, xmm0
    or      rax, r8
    movq    xmm0, rax
    ret
.special:
    addsd   xmm0, xmm0          ; +-0, +-Inf unchanged; NaN quieted
    ret

mathfn_unary_arrays umath_cbrt_f64, umath_cbrt_f64, 8

%endif ; GUARD_LIB_UMATH_MATH_FN_CBRT_F64_ASM
