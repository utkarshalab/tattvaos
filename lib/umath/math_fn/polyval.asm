%ifndef GUARD_LIB_UMATH_MATH_FN_POLYVAL_ASM
%define GUARD_LIB_UMATH_MATH_FN_POLYVAL_ASM
; =============================================================================
; umath - unified math library
; math_fn/polyval.asm - polynomial evaluation (Horner)
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
;   umath_polyval_f64(c, n, x)  c[0]*x^(n-1) + c[1]*x^(n-2) + ... + c[n-1]
;
; Coefficients are given highest degree first, the order Horner's rule
; consumes them: p = c[0]; p = p*x + c[k] for k = 1 .. n-1. Each step
; rounds twice (multiply, add), so for well-scaled coefficients the result
; is within a few ULP. n = 0 gives +0.
;
; Also used internally by the special functions (erf_f64.asm,
; gamma_f64.asm), which inline the same loop as the mathfn_horner macro
; below. The function itself touches only rcx, xmm0 and xmm1.
; =============================================================================

bits 64

section .text

; -----------------------------------------------------------------------------
; umath_polyval_f64 - Horner evaluation
; args:    rdi = const double *c (highest degree first), rsi = n, xmm0 = x
; returns: xmm0 = polynomial value
; Clobbers rcx, xmm1.
; -----------------------------------------------------------------------------
global umath_polyval_f64
umath_polyval_f64:
    movapd  xmm1, xmm0          ; x
    xorpd   xmm0, xmm0
    test    rsi, rsi
    jz      .done
    movsd   xmm0, [rdi]
    mov     ecx, 1
.loop:
    cmp     rcx, rsi
    jae     .done
    mulsd   xmm0, xmm1
    addsd   xmm0, [rdi + rcx*8]
    inc     rcx
    jmp     .loop
.done:
    ret

; -----------------------------------------------------------------------------
; mathfn_horner - inline Horner over a constant table
; args: %1 = table label, %2 = number of coefficients, %3 = register with x,
;       %4 = destination register (must differ from %3)
; -----------------------------------------------------------------------------
%macro mathfn_horner 4
    movsd   %4, [rel %1]
%assign %%k 1
%rep %2 - 1
    mulsd   %4, %3
    addsd   %4, [rel %1 + %%k*8]
%assign %%k %%k + 1
%endrep
%endmacro

%endif ; GUARD_LIB_UMATH_MATH_FN_POLYVAL_ASM
