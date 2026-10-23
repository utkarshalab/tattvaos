%ifndef GUARD_LIB_UMATH_MATH_FN_LOG2_F64_ASM
%define GUARD_LIB_UMATH_MATH_FN_LOG2_F64_ASM
; =============================================================================
; umath - unified math library
; math_fn/log2_f64.asm - double-precision log base 2
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; x = m * 2^e with m in [sqrt(2)/2, sqrt(2)), read exactly from the IEEE
; bits (subnormals pre-scaled by 2^54), then
;
;     log2(x) = e + ln(m) * log2(e)
;
; ln(m) comes from umath_log_f64, which on that range evaluates its series
; directly (its own exponent is 0). Splitting e out exactly, rather than
; computing ln(x) / ln(2), keeps the integer part free of rounding:
; log2(2^k) is exactly k, and the result is a few ULP elsewhere.
;
; log2f64__split (internal) is shared with log10_f64.asm.
;
;   - 0 gives -Inf, x < 0 gives NaN, +Inf gives +Inf, NaN propagates.
; =============================================================================

bits 64

%include "lib/umath/math_fn/log_f64.asm"
%include "lib/umath/math_fn/loops.asm"

section .rodata
align 8
log2f64_dbl_min:    dq 2.2250738585072014e-308
log2f64_two_54:     dq 18014398509481984.0
log2f64_sqrt2:      dq 1.4142135623730951
log2f64_half:       dq 0.5
log2f64_log2e:      dq 1.4426950408889634
log2f64_inf:        dq 0x7FF0000000000000
log2f64_neg_inf:    dq 0xFFF0000000000000
log2f64_nan:        dq 0x7FF8000000000000

section .text

; -----------------------------------------------------------------------------
; log2f64__split - internal: x = m * 2^e, m in [sqrt(2)/2, sqrt(2))
; args:    xmm0 = x, positive and finite (subnormals allowed)
; returns: xmm0 = ln(m), rax = e
; Clobbers what umath_log_f64 clobbers, plus rdx.
; -----------------------------------------------------------------------------
log2f64__split:
    sub     rsp, 24
    xor     ecx, ecx
    comisd  xmm0, [rel log2f64_dbl_min]
    jae     .normal
    mulsd   xmm0, [rel log2f64_two_54]  ; exact
    mov     ecx, 54
.normal:
    movq    rax, xmm0
    mov     rdx, rax
    shr     rdx, 52             ; biased exponent (sign bit is 0)
    sub     rdx, 1023
    sub     rdx, rcx            ; undo the pre-scale
    mov     rcx, 0x000FFFFFFFFFFFFF
    and     rax, rcx
    mov     rcx, 0x3FF0000000000000
    or      rax, rcx
    movq    xmm0, rax           ; m in [1, 2)
    comisd  xmm0, [rel log2f64_sqrt2]
    jbe     .reduced
    mulsd   xmm0, [rel log2f64_half]  ; exact
    inc     rdx
.reduced:
    mov     [rsp], rdx
    call    umath_log_f64
    mov     rax, [rsp]
    add     rsp, 24
    ret

; -----------------------------------------------------------------------------
; umath_log2_f64 - scalar log2(x)
; args:    xmm0 = x
; returns: xmm0 = log2(x)
; -----------------------------------------------------------------------------
global umath_log2_f64
umath_log2_f64:
    xorpd   xmm1, xmm1
    ucomisd xmm0, xmm1
    jp      .nan
    jbe     .not_positive
    ucomisd xmm0, [rel log2f64_inf]
    je      .ret
    sub     rsp, 8
    call    log2f64__split
    mulsd   xmm0, [rel log2f64_log2e]
    cvtsi2sd xmm1, rax
    addsd   xmm0, xmm1
    add     rsp, 8
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

mathfn_unary_arrays umath_log2_f64, umath_log2_f64, 8

%endif ; GUARD_LIB_UMATH_MATH_FN_LOG2_F64_ASM
