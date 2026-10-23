%ifndef GUARD_LIB_UMATH_MATH_FN_TANH_F64_ASM
%define GUARD_LIB_UMATH_MATH_FN_TANH_F64_ASM
; =============================================================================
; umath - unified math library
; math_fn/tanh_f64.asm - double-precision hyperbolic tangent
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; tanh(-x) = -tanh(x); with a = |x|:
;
;   a < 2^-28        tanh(a) = a
;   a < 22           t = expm1(2a), tanh(a) = t / (t + 2)
;                    -- (e^2a - 1)/(e^2a + 1) without the cancellation
;   otherwise        1 (1 - tanh(22) = 1.5e-19, below half an ULP)
;
; +-0 return themselves, +-Inf give +-1, NaN propagates (quieted).
; =============================================================================

bits 64

%include "lib/umath/math_fn/expm1_f64.asm"
%include "lib/umath/math_fn/loops.asm"

section .rodata
align 8
tanhf64_tiny:       dq 0x3E30000000000000       ; 2^-28
tanhf64_22:         dq 22.0
tanhf64_one:        dq 1.0
tanhf64_two:        dq 2.0

section .text

; -----------------------------------------------------------------------------
; umath_tanh_f64 - scalar hyperbolic tangent
; args:    xmm0 = x
; returns: xmm0 = tanh(x), in [-1, 1]
; -----------------------------------------------------------------------------
global umath_tanh_f64
umath_tanh_f64:
    ucomisd xmm0, xmm0
    jp      .nan
    movq    rax, xmm0
    mov     rdx, rax
    btr     rax, 63
    xor     rdx, rax            ; sign bit
    movq    xmm0, rax
    comisd  xmm0, [rel tanhf64_tiny]
    jb      .signed
    comisd  xmm0, [rel tanhf64_22]
    jae     .one
    sub     rsp, 24
    mov     [rsp], rdx
    addsd   xmm0, xmm0          ; 2a, exact
    call    umath_expm1_f64     ; t
    movapd  xmm1, xmm0
    addsd   xmm1, [rel tanhf64_two]
    divsd   xmm0, xmm1          ; t / (t + 2)
    mov     rdx, [rsp]
    add     rsp, 24
    jmp     .signed
.one:
    movsd   xmm0, [rel tanhf64_one]
.signed:
    movq    rax, xmm0
    or      rax, rdx
    movq    xmm0, rax
    ret
.nan:
    addsd   xmm0, xmm0
    ret

mathfn_unary_arrays umath_tanh_f64, umath_tanh_f64, 8

%endif ; GUARD_LIB_UMATH_MATH_FN_TANH_F64_ASM
