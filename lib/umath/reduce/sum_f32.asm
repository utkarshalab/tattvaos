%ifndef GUARD_LIB_UMATH_REDUCE_SUM_F32_ASM
%define GUARD_LIB_UMATH_REDUCE_SUM_F32_ASM
; =============================================================================
; umath - unified math library
; reduce/sum_f32.asm - sum and mean of a float array
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
;   - umath_reduce_sum_f32: pairwise summation in float
;     (stability/pairwise_f32.asm), error growing with log2(n).
;   - umath_reduce_mean_f32: compensated sum accumulated in double
;     (stability/kahan_f32.asm), divided by n in double, rounded to float
;     once; NaN for an empty array.
; =============================================================================

bits 64

%include "lib/umath/stability/pairwise_f32.asm"
%include "lib/umath/stability/kahan_f32.asm"

section .rodata
align 8
redsumf32_nan:  dq 0x7FF8000000000000

section .text

; -----------------------------------------------------------------------------
; umath_reduce_sum_f32 - sum of an array of floats (pairwise)
; args:    rdi = source pointer (src)
;          rsi = size of array (count)
; returns: xmm0 = sum (0.0f for an empty or NULL array)
; -----------------------------------------------------------------------------
global umath_reduce_sum_f32
umath_reduce_sum_f32:
    jmp     umath_pairwise_sum_f32

; -----------------------------------------------------------------------------
; umath_reduce_mean_f32 - arithmetic mean of an array of floats
; args:    rdi = source pointer (src)
;          rsi = size of array (count)
; returns: xmm0 = mean as float (NaN for an empty or NULL array)
; -----------------------------------------------------------------------------
global umath_reduce_mean_f32
umath_reduce_mean_f32:
    movsd   xmm0, [rel redsumf32_nan]
    test    rdi, rdi
    jz      .narrow
    test    rsi, rsi
    jz      .narrow
    push    rsi                 ; count; also aligns rsp for the call
    call    kahanf32__sum_d     ; compensated sum, still in double
    pop     rsi
    cvtsi2sd xmm1, rsi
    divsd   xmm0, xmm1
.narrow:
    cvtsd2ss xmm0, xmm0         ; single rounding to float
    ret

%endif ; GUARD_LIB_UMATH_REDUCE_SUM_F32_ASM
