%ifndef GUARD_LIB_UMATH_REDUCE_PROD_F32_ASM
%define GUARD_LIB_UMATH_REDUCE_PROD_F32_ASM
; =============================================================================
; umath - unified math library
; reduce/prod_f32.asm - product of a float array without intermediate overflow
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; Floats are widened exactly and folded with the same mantissa/exponent
; scheme as prod_f64.asm (see there), so neither intermediate overflow nor
; float's narrow range can spoil the result; the double product is rounded
; to float once at the end (overflowing to +/-Inf or underflowing through
; float subnormals as the true product does). Same special values.
; =============================================================================

bits 64

%include "lib/umath/reduce/prod_f64.asm"

section .text

; -----------------------------------------------------------------------------
; umath_reduce_prod_f32 - product of an array of floats
; args:    rdi = source pointer (src)
;          rsi = size of array (count)
; returns: xmm0 = product as float (1.0f for an empty or NULL array)
; -----------------------------------------------------------------------------
global umath_reduce_prod_f32
umath_reduce_prod_f32:
    movsd   xmm0, [rel prodf64_one]
    xor     r8d, r8d
    xor     r9d, r9d
    xor     r10d, r10d
    xor     r11d, r11d
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done
.loop:
    cvtss2sd xmm1, [rdi]
    prodf64_step
    add     rdi, 4
    dec     rsi
    jnz     .loop
.done:
    sub     rsp, 8              ; keep rsp 16-byte aligned at the call
    call    prodf64__finish
    add     rsp, 8
    cvtsd2ss xmm0, xmm0
    ret
.nan:
    movsd   xmm0, [rel prodf64_nan]
    cvtsd2ss xmm0, xmm0
    ret

%endif ; GUARD_LIB_UMATH_REDUCE_PROD_F32_ASM
