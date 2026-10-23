%ifndef GUARD_LIB_UMATH_MATH_FN_SINH_F64_ASM
%define GUARD_LIB_UMATH_MATH_FN_SINH_F64_ASM
; =============================================================================
; umath - unified math library
; math_fn/sinh_f64.asm - double-precision hyperbolic sine
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; sinh(-x) = -sinh(x); with a = |x|:
;
;   a < 2^-28        sinh(a) = a (the a^3/6 term is below half an ULP)
;   a < 22           t = expm1(a), sinh(a) = (t + t/(t + 1)) / 2
;                    -- (e^a - e^-a)/2 rewritten so nothing cancels
;   a < 709.7        e^a / 2 (e^-a is below 2^-63 of the result)
;   otherwise        w = e^(a/2), (w/2) * w -- finite up to the true
;                    overflow point ~710.4758, +Inf beyond
;
; +-0 and +-Inf return themselves, NaN propagates (quieted).
; =============================================================================

bits 64

%include "lib/umath/math_fn/exp_f64.asm"
%include "lib/umath/math_fn/expm1_f64.asm"
%include "lib/umath/math_fn/loops.asm"

section .rodata
align 8
sinhf64_tiny:       dq 0x3E30000000000000       ; 2^-28
sinhf64_22:         dq 22.0
sinhf64_big:        dq 709.7
sinhf64_half:       dq 0.5
sinhf64_one:        dq 1.0

section .text

; -----------------------------------------------------------------------------
; umath_sinh_f64 - scalar hyperbolic sine
; args:    xmm0 = x
; returns: xmm0 = sinh(x)
; -----------------------------------------------------------------------------
global umath_sinh_f64
umath_sinh_f64:
    ucomisd xmm0, xmm0
    jp      .nan
    movq    rax, xmm0
    mov     rdx, rax
    btr     rax, 63
    xor     rdx, rax            ; sign bit
    movq    xmm0, rax           ; a
    comisd  xmm0, [rel sinhf64_tiny]
    jb      .tiny
    sub     rsp, 24
    mov     [rsp], rdx
    comisd  xmm0, [rel sinhf64_22]
    jae     .large
    call    umath_expm1_f64     ; t
    movapd  xmm1, xmm0
    addsd   xmm1, [rel sinhf64_one]
    movapd  xmm2, xmm0
    divsd   xmm2, xmm1          ; t / (t + 1)
    addsd   xmm0, xmm2
    mulsd   xmm0, [rel sinhf64_half]
    jmp     .signed
.large:
    comisd  xmm0, [rel sinhf64_big]
    jae     .huge
    call    umath_exp_f64
    mulsd   xmm0, [rel sinhf64_half]
    jmp     .signed
.huge:
    mulsd   xmm0, [rel sinhf64_half]
    call    umath_exp_f64       ; w = e^(a/2)
    movapd  xmm1, xmm0
    mulsd   xmm1, [rel sinhf64_half]
    mulsd   xmm0, xmm1          ; (w/2) * w
.signed:
    mov     rdx, [rsp]
    add     rsp, 24
.tiny:
    movq    rax, xmm0
    or      rax, rdx
    movq    xmm0, rax
    ret
.nan:
    addsd   xmm0, xmm0
    ret

mathfn_unary_arrays umath_sinh_f64, umath_sinh_f64, 8

%endif ; GUARD_LIB_UMATH_MATH_FN_SINH_F64_ASM
