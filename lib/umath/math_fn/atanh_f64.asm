%ifndef GUARD_LIB_UMATH_MATH_FN_ATANH_F64_ASM
%define GUARD_LIB_UMATH_MATH_FN_ATANH_F64_ASM
; =============================================================================
; umath - unified math library
; math_fn/atanh_f64.asm - double-precision inverse hyperbolic tangent
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; atanh(-x) = -atanh(x); with a = |x|, atanh(a) = ln((1 + a)/(1 - a)) / 2
; = log1p(2a / (1 - a)) / 2:
;
;   a < 2^-28        a
;   a < 0.5          log1p(2a + 2a*a / (1 - a)) / 2 -- the same value,
;                    with the leading 2a exact so small a keeps its
;                    relative accuracy
;   a < 1            log1p(2a / (1 - a)) / 2, 1 - a exact (Sterbenz)
;
;   - +-1 give +-Inf, |x| > 1 gives NaN, +-0 return themselves;
;   - NaN propagates (quieted).
; =============================================================================

bits 64

%include "lib/umath/math_fn/log1p_f64.asm"
%include "lib/umath/math_fn/loops.asm"

section .rodata
align 8
atanhf64_tiny:      dq 0x3E30000000000000       ; 2^-28
atanhf64_half:      dq 0.5
atanhf64_one:       dq 1.0
atanhf64_inf:       dq 0x7FF0000000000000
atanhf64_nan:       dq 0x7FF8000000000000

section .text

; -----------------------------------------------------------------------------
; umath_atanh_f64 - scalar inverse hyperbolic tangent
; args:    xmm0 = x
; returns: xmm0 = atanh(x)
; -----------------------------------------------------------------------------
global umath_atanh_f64
umath_atanh_f64:
    ucomisd xmm0, xmm0
    jp      .nan
    movq    rax, xmm0
    mov     rdx, rax
    btr     rax, 63
    xor     rdx, rax            ; sign bit
    movq    xmm0, rax           ; a
    comisd  xmm0, [rel atanhf64_one]
    ja      .domain
    je      .inf
    comisd  xmm0, [rel atanhf64_tiny]
    jb      .signed
    sub     rsp, 24
    mov     [rsp], rdx
    movsd   xmm1, [rel atanhf64_one]
    subsd   xmm1, xmm0          ; 1 - a
    movapd  xmm2, xmm0
    addsd   xmm2, xmm0          ; 2a, exact
    comisd  xmm0, [rel atanhf64_half]
    jae     .upper
    mulsd   xmm0, xmm2          ; 2a*a
    divsd   xmm0, xmm1
    addsd   xmm0, xmm2          ; 2a + 2a*a/(1 - a)
    jmp     .log
.upper:
    divsd   xmm2, xmm1
    movapd  xmm0, xmm2          ; 2a / (1 - a)
.log:
    call    umath_log1p_f64
    mulsd   xmm0, [rel atanhf64_half]
    mov     rdx, [rsp]
    add     rsp, 24
    jmp     .signed
.inf:
    movsd   xmm0, [rel atanhf64_inf]
.signed:
    movq    rax, xmm0
    or      rax, rdx
    movq    xmm0, rax
    ret
.domain:
    movsd   xmm0, [rel atanhf64_nan]
    ret
.nan:
    addsd   xmm0, xmm0
    ret

mathfn_unary_arrays umath_atanh_f64, umath_atanh_f64, 8

%endif ; GUARD_LIB_UMATH_MATH_FN_ATANH_F64_ASM
