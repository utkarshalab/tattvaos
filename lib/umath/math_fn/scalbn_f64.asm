%ifndef GUARD_LIB_UMATH_MATH_FN_SCALBN_F64_ASM
%define GUARD_LIB_UMATH_MATH_FN_SCALBN_F64_ASM
; =============================================================================
; umath - unified math library
; math_fn/scalbn_f64.asm - x * 2^n for doubles (scalbn / ldexp)
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; The result is x * 2^n rounded once: exact whenever it is a normal number,
; one rounding when it lands in the subnormal range, +-Inf on overflow and
; +-0 on full underflow. NaN, +-Inf and +-0 come back unchanged.
;
; 2^n is applied as up to three multiplications by normal powers of two:
;   - n > 1023: multiply by 2^1023 (exact, or overflow to Inf) and reduce n,
;     at most twice, then clamp (any larger n overflows anyway);
;   - n < -1022: multiply by 2^-969 = 2^-1022 * 2^53 and raise n by 969, at
;     most twice, then clamp. Stepping by 2^-969 rather than 2^-1022 keeps
;     the intermediate 53 bits above the subnormal range, so the only
;     rounding happens in the final multiply -- a 2^-1022 step could round
;     once into a subnormal and again in the last step (double rounding).
;
; Clobbers rax, xmm1.
; =============================================================================

bits 64

section .rodata
align 8
scalbnf64_two_1023:     dq 0x7FE0000000000000      ; 2^1023
scalbnf64_two_m969:     dq 0x0360000000000000      ; 2^-969

section .text

; -----------------------------------------------------------------------------
; umath_scalbn_f64 / umath_ldexp_f64 - x * 2^n
; args:    xmm0 = x
;          rdi  = n (signed 64-bit)
; returns: xmm0 = x * 2^n
; -----------------------------------------------------------------------------
global umath_scalbn_f64
global umath_ldexp_f64
umath_ldexp_f64:
umath_scalbn_f64:
    mov     rax, rdi
    cmp     rax, 1023
    jle     .not_big
    mulsd   xmm0, [rel scalbnf64_two_1023]
    sub     rax, 1023
    cmp     rax, 1023
    jle     .apply
    mulsd   xmm0, [rel scalbnf64_two_1023]
    sub     rax, 1023
    cmp     rax, 1023
    jle     .apply
    mov     eax, 1023
    jmp     .apply
.not_big:
    cmp     rax, -1022
    jge     .apply
    mulsd   xmm0, [rel scalbnf64_two_m969]
    add     rax, 969
    cmp     rax, -1022
    jge     .apply
    mulsd   xmm0, [rel scalbnf64_two_m969]
    add     rax, 969
    cmp     rax, -1022
    jge     .apply
    mov     rax, -1022
.apply:
    add     rax, 1023           ; biased exponent of 2^n, in [1, 2046]
    shl     rax, 52
    movq    xmm1, rax
    mulsd   xmm0, xmm1
    ret

%endif ; GUARD_LIB_UMATH_MATH_FN_SCALBN_F64_ASM
