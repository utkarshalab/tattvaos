%ifndef GUARD_LIB_UMATH_MATH_FN_EXP10_F64_ASM
%define GUARD_LIB_UMATH_MATH_FN_EXP10_F64_ASM
; =============================================================================
; umath - unified math library
; math_fn/exp10_f64.asm - double-precision 10^x
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; 10^x = 2^k * e^(r*ln10) with k = round(x * log2(10)) and
; r = x - k*log10(2). log10(2) is split as hi + lo, hi carrying 40
; significant bits: |k| <= 1329 after the clamp needs 11 bits, so k*hi is
; exact, x - k*hi is exact (the two are within a factor of two whenever
; k != 0), and k*lo adds only a rounding far below one ULP. r lies in
; [-0.151, 0.151], so r*ln10 is in [-0.35, 0.35]; e^() comes from
; umath_exp_f64 and 2^k from umath_scalbn_f64.
;
;   - x = 0, 1, ..., 22 return 10^x exactly (all exactly representable),
;     independent of exp's rounding;
;   - overflow to +Inf above ~308.25, underflow to +0 below ~-323.3;
;   - +-Inf give +Inf / +0, NaN propagates (quieted).
; =============================================================================

bits 64

%include "lib/umath/math_fn/exp_f64.asm"
%include "lib/umath/math_fn/scalbn_f64.asm"
%include "lib/umath/math_fn/loops.asm"
%include "lib/umath/cpuid/fallback.asm"

section .rodata
align 8
exp10f64_max:       dq 400.0
exp10f64_min:       dq -400.0
exp10f64_log2_10:   dq 3.321928094887362
exp10f64_lg2_hi:    dq 0x3FD34413509F8000       ; log10(2), 40 bits
exp10f64_lg2_lo:    dq 0xBD380433B83B532A       ; log10(2) - hi
exp10f64_ln10:      dq 2.302585092994046
exp10f64_22:        dq 22.0
exp10f64_pow10:                                 ; 10^0 .. 10^22, all exact
    dq 1.0e0, 1.0e1, 1.0e2, 1.0e3, 1.0e4, 1.0e5, 1.0e6, 1.0e7
    dq 1.0e8, 1.0e9, 1.0e10, 1.0e11, 1.0e12, 1.0e13, 1.0e14, 1.0e15
    dq 1.0e16, 1.0e17, 1.0e18, 1.0e19, 1.0e20, 1.0e21, 1.0e22

section .text

; -----------------------------------------------------------------------------
; umath_exp10_f64 - scalar 10^x
; args:    xmm0 = x
; returns: xmm0 = 10^x
; -----------------------------------------------------------------------------
global umath_exp10_f64
umath_exp10_f64:
    ucomisd xmm0, xmm0
    jp      .nan
    ; exact powers: x integral and 0 <= x <= 22
    xorpd   xmm1, xmm1
    comisd  xmm0, xmm1
    jb      .general
    comisd  xmm0, [rel exp10f64_22]
    ja      .general
    cvttsd2si eax, xmm0
    cvtsi2sd xmm1, eax
    ucomisd xmm1, xmm0
    jne     .general
    lea     rcx, [rel exp10f64_pow10]
    movsd   xmm0, [rcx + rax*8]
    ret
.general:
    sub     rsp, 24
    movsd   xmm1, [rel exp10f64_max]
    minsd   xmm1, xmm0
    movsd   xmm0, [rel exp10f64_min]
    maxsd   xmm0, xmm1          ; x clamped to [-400, 400]
    movsd   xmm1, xmm0
    mulsd   xmm1, [rel exp10f64_log2_10]
    um_roundsd xmm1, xmm1, 0    ; k
    cvttsd2si rax, xmm1
    mov     [rsp], rax
    movsd   xmm2, xmm1
    mulsd   xmm2, [rel exp10f64_lg2_hi]
    subsd   xmm0, xmm2          ; x - k*hi (exact)
    mulsd   xmm1, [rel exp10f64_lg2_lo]
    subsd   xmm0, xmm1          ; r
    mulsd   xmm0, [rel exp10f64_ln10]
    call    umath_exp_f64
    mov     rdi, [rsp]
    call    umath_scalbn_f64
    add     rsp, 24
    ret
.nan:
    addsd   xmm0, xmm0
    ret

mathfn_unary_arrays umath_exp10_f64, umath_exp10_f64, 8

%endif ; GUARD_LIB_UMATH_MATH_FN_EXP10_F64_ASM
