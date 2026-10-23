%ifndef GUARD_LIB_UMATH_MATH_FN_LOG10_F64_ASM
%define GUARD_LIB_UMATH_MATH_FN_LOG10_F64_ASM
; =============================================================================
; umath - unified math library
; math_fn/log10_f64.asm - double-precision log base 10
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; Same exact decomposition as log2_f64.asm (x = m * 2^e), then
;
;     log10(x) = e*hi + (e*lo + ln(m) * log10(e))
;
; with log10(2) = hi + lo, hi carrying 40 significant bits so e*hi is exact
; for every exponent. The small terms are added first and the exact e*hi
; last, so the result is rounded once at the end.
;
; Exact powers of ten 10^0 .. 10^22 (the ones a double holds exactly)
; return exactly 0 .. 22.
;
;   - 0 gives -Inf, x < 0 gives NaN, +Inf gives +Inf, NaN propagates.
; =============================================================================

bits 64

%include "lib/umath/math_fn/log2_f64.asm"
%include "lib/umath/math_fn/loops.asm"
%include "lib/umath/cpuid/fallback.asm"

section .rodata
align 8
log10f64_lg2_hi:    dq 0x3FD34413509F8000       ; log10(2), 40 bits
log10f64_lg2_lo:    dq 0xBD380433B83B532A       ; log10(2) - hi
log10f64_log10e:    dq 0.4342944819032518
log10f64_pow10:                                 ; 10^0 .. 10^22, all exact
    dq 1.0e0, 1.0e1, 1.0e2, 1.0e3, 1.0e4, 1.0e5, 1.0e6, 1.0e7
    dq 1.0e8, 1.0e9, 1.0e10, 1.0e11, 1.0e12, 1.0e13, 1.0e14, 1.0e15
    dq 1.0e16, 1.0e17, 1.0e18, 1.0e19, 1.0e20, 1.0e21, 1.0e22

section .text

; -----------------------------------------------------------------------------
; umath_log10_f64 - scalar log10(x)
; args:    xmm0 = x
; returns: xmm0 = log10(x)
; -----------------------------------------------------------------------------
global umath_log10_f64
umath_log10_f64:
    xorpd   xmm1, xmm1
    ucomisd xmm0, xmm1
    jp      .nan
    jbe     .not_positive
    ucomisd xmm0, [rel log2f64_inf]
    je      .ret
    sub     rsp, 24
    movsd   [rsp], xmm0         ; x
    call    log2f64__split
    cvtsi2sd xmm1, rax          ; e
    movsd   xmm2, xmm1
    mulsd   xmm2, [rel log10f64_lg2_hi]  ; e*hi, exact
    mulsd   xmm1, [rel log10f64_lg2_lo]
    mulsd   xmm0, [rel log10f64_log10e]
    addsd   xmm0, xmm1
    addsd   xmm0, xmm2
    ; exact powers of ten: if x == 10^n for 0 <= n <= 22, return n
    um_roundsd xmm1, xmm0, 0
    cvttsd2si eax, xmm1
    cmp     eax, 22
    ja      .done               ; unsigned: also rejects n < 0
    lea     rcx, [rel log10f64_pow10]
    movsd   xmm2, [rsp]
    ucomisd xmm2, [rcx + rax*8]
    jne     .done
    movapd  xmm0, xmm1
.done:
    add     rsp, 24
.ret:
    ret
.not_positive:
    je      .zero
    movsd   xmm0, [rel log2f64_nan]
    ret
.zero:
    movsd   xmm0, [rel log2f64_neg_inf]
    ret
.nan:
    addsd   xmm0, xmm0
    ret

mathfn_unary_arrays umath_log10_f64, umath_log10_f64, 8

%endif ; GUARD_LIB_UMATH_MATH_FN_LOG10_F64_ASM
