%ifndef GUARD_LIB_UMATH_REDUCE_SUM_F64_ASM
%define GUARD_LIB_UMATH_REDUCE_SUM_F64_ASM
; =============================================================================
; umath - unified math library
; reduce/sum_f64.asm - sum and mean of a double array
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; The reduce/ entry points pick an algorithm from stability/ rather than
; reimplementing one:
;
;   - umath_reduce_sum_f64: pairwise summation (stability/pairwise_f64.asm),
;     error growing with log2(n), essentially the cost of a plain loop. For
;     a result within 2 ULP whatever the cancellation, call
;     umath_kahan_sum_f64 directly.
;   - umath_reduce_mean_f64: compensated sum / n. A mean is usually reported
;     as is, so it gets the accurate sum; NaN for an empty array.
; =============================================================================

bits 64

%include "lib/umath/stability/pairwise_f64.asm"
%include "lib/umath/stability/kahan_f64.asm"

section .rodata
align 8
redsumf64_nan:  dq 0x7FF8000000000000

section .text

; -----------------------------------------------------------------------------
; umath_reduce_sum_f64 - sum of an array of doubles (pairwise)
; args:    rdi = source pointer (src)
;          rsi = size of array (count)
; returns: xmm0 = sum (0.0 for an empty or NULL array)
; -----------------------------------------------------------------------------
global umath_reduce_sum_f64
umath_reduce_sum_f64:
    jmp     umath_pairwise_sum_f64

; -----------------------------------------------------------------------------
; umath_reduce_mean_f64 - arithmetic mean of an array of doubles
; args:    rdi = source pointer (src)
;          rsi = size of array (count)
; returns: xmm0 = mean (NaN for an empty or NULL array)
; -----------------------------------------------------------------------------
global umath_reduce_mean_f64
umath_reduce_mean_f64:
    test    rdi, rdi
    jz      .nan
    test    rsi, rsi
    jz      .nan
    push    rsi                 ; count; also aligns rsp for the call
    call    umath_kahan_sum_f64
    pop     rsi
    cvtsi2sd xmm1, rsi
    divsd   xmm0, xmm1
    ret
.nan:
    movsd   xmm0, [rel redsumf64_nan]
    ret

%endif ; GUARD_LIB_UMATH_REDUCE_SUM_F64_ASM
