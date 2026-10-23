%ifndef GUARD_LIB_UMATH_MATH_FN_ASINH_F64_ASM
%define GUARD_LIB_UMATH_MATH_FN_ASINH_F64_ASM
; =============================================================================
; umath - unified math library
; math_fn/asinh_f64.asm - double-precision inverse hyperbolic sine
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; asinh(-x) = -asinh(x); with a = |x|, asinh(a) = ln(a + sqrt(a^2 + 1)):
;
;   a < 2^-28        a
;   a <= 2           log1p(a + a^2 / (1 + sqrt(1 + a^2)))
;                    -- the "+1" moved out into log1p so small a keeps
;                    its relative accuracy
;   a <= 2^28        ln(2a + 1 / (a + sqrt(a^2 + 1)))
;   otherwise        ln(a) + ln(2) -- a^2 + 1 = a^2 there, and 2a could
;                    overflow
;
; +-0 and +-Inf return themselves, NaN propagates (quieted).
; =============================================================================

bits 64

%include "lib/umath/math_fn/log_f64.asm"
%include "lib/umath/math_fn/log1p_f64.asm"
%include "lib/umath/math_fn/loops.asm"

section .rodata
align 8
asinhf64_tiny:      dq 0x3E30000000000000       ; 2^-28
asinhf64_two:       dq 2.0
asinhf64_big:       dq 0x41B0000000000000       ; 2^28
asinhf64_one:       dq 1.0
asinhf64_ln2:       dq 0.6931471805599453
asinhf64_inf:       dq 0x7FF0000000000000

section .text

; -----------------------------------------------------------------------------
; umath_asinh_f64 - scalar inverse hyperbolic sine
; args:    xmm0 = x
; returns: xmm0 = asinh(x)
; -----------------------------------------------------------------------------
global umath_asinh_f64
umath_asinh_f64:
    ucomisd xmm0, xmm0
    jp      .nan
    movq    rax, xmm0
    mov     rdx, rax
    btr     rax, 63
    xor     rdx, rax            ; sign bit
    movq    xmm0, rax           ; a
    comisd  xmm0, [rel asinhf64_tiny]
    jb      .signed
    ucomisd xmm0, [rel asinhf64_inf]
    je      .signed
    sub     rsp, 24
    mov     [rsp], rdx
    comisd  xmm0, [rel asinhf64_two]
    ja      .medium
    movapd  xmm1, xmm0
    mulsd   xmm1, xmm0          ; a^2
    movsd   xmm2, [rel asinhf64_one]
    addsd   xmm2, xmm1
    sqrtsd  xmm2, xmm2
    addsd   xmm2, [rel asinhf64_one]  ; 1 + sqrt(1 + a^2)
    divsd   xmm1, xmm2
    addsd   xmm0, xmm1
    call    umath_log1p_f64
    jmp     .done
.medium:
    comisd  xmm0, [rel asinhf64_big]
    ja      .large
    movapd  xmm1, xmm0
    mulsd   xmm1, xmm0
    addsd   xmm1, [rel asinhf64_one]
    sqrtsd  xmm1, xmm1
    addsd   xmm1, xmm0          ; a + sqrt(a^2 + 1)
    movsd   xmm2, [rel asinhf64_one]
    divsd   xmm2, xmm1
    addsd   xmm0, xmm0
    addsd   xmm0, xmm2
    call    umath_log_f64
    jmp     .done
.large:
    call    umath_log_f64
    addsd   xmm0, [rel asinhf64_ln2]
.done:
    mov     rdx, [rsp]
    add     rsp, 24
.signed:
    movq    rax, xmm0
    or      rax, rdx
    movq    xmm0, rax
    ret
.nan:
    addsd   xmm0, xmm0
    ret

mathfn_unary_arrays umath_asinh_f64, umath_asinh_f64, 8

%endif ; GUARD_LIB_UMATH_MATH_FN_ASINH_F64_ASM
