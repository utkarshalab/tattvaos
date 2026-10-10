%ifndef GUARD_LIB_UMATH_STABILITY_KAHAN_F32_ASM
%define GUARD_LIB_UMATH_STABILITY_KAHAN_F32_ASM
; =============================================================================
; umath - unified math library
; stability/kahan_f32.asm - compensated summation of single-precision data
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; Floats are widened to double (exact) and summed with the same Neumaier
; compensation as kahan_f64.asm, then the total is rounded to float once.
; Compensated double accumulation carries roughly 2 x 53 bits, far more
; than float's 24, so the result is the correctly rounded float sum except
; in pathological cancellation cases. This costs a cvtps2pd per pair of
; elements and is still far cheaper than any float-only scheme with the
; same accuracy.
;
; The streaming state is the f64 one ({ f64 sum, f64 comp }), so
; umath_kahan_init_f64 initializes it and f32 and f64 values can be mixed.
; =============================================================================

bits 64

%include "lib/umath/stability/kahan_f64.asm"

section .text

; -----------------------------------------------------------------------------
; umath_kahan_sum_f32 - compensated sum of an array of floats
; args:    rdi = source pointer (src)
;          rsi = size of array (count)
; returns: xmm0 = sum as float (0.0f for an empty or NULL array)
; -----------------------------------------------------------------------------
global umath_kahan_sum_f32
umath_kahan_sum_f32:
    xorpd   xmm0, xmm0          ; s lanes 0-1 (double)
    xorpd   xmm1, xmm1          ; c lanes 0-1
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done

    xorpd   xmm2, xmm2          ; s lanes 2-3
    xorpd   xmm3, xmm3          ; c lanes 2-3
    movapd  xmm15, [rel kahanf64_abs_mask]

    mov     rcx, rsi
    shr     rcx, 2              ; count of 4-float blocks
    jz      .fold

.loop4:
    cvtps2pd xmm4, [rdi]        ; floats 0-1 widened (exact)
    cvtps2pd xmm5, [rdi + 8]    ; floats 2-3
    kahanf64_step_pd xmm0, xmm1, xmm4, xmm6, xmm7, xmm8
    kahanf64_step_pd xmm2, xmm3, xmm5, xmm9, xmm10, xmm11
    add     rdi, 16
    dec     rcx
    jnz     .loop4

.fold:
    addpd   xmm1, xmm3
    kahanf64_step_pd xmm0, xmm1, xmm2, xmm6, xmm7, xmm8
    movapd  xmm4, xmm0
    unpckhpd xmm4, xmm4
    movapd  xmm5, xmm1
    unpckhpd xmm5, xmm5
    addsd   xmm1, xmm5
    kahanf64_step_sd xmm0, xmm1, xmm4, xmm6, xmm7, xmm8

    and     rsi, 3
    jz      .finish
.tail:
    cvtss2sd xmm4, [rdi]
    kahanf64_step_sd xmm0, xmm1, xmm4, xmm6, xmm7, xmm8
    add     rdi, 4
    dec     rsi
    jnz     .tail

.finish:
    call    kahanf64__finish
    cvtsd2ss xmm0, xmm0         ; single rounding to float
    ret
.done:
    xorps   xmm0, xmm0
    ret

; -----------------------------------------------------------------------------
; umath_kahan_add_f32 - add one float to a streaming accumulator
; args:    rdi = pointer to state (see umath_kahan_init_f64)
;          xmm0 = value to add (float)
; returns: void
; -----------------------------------------------------------------------------
global umath_kahan_add_f32
umath_kahan_add_f32:
    cvtss2sd xmm0, xmm0
    jmp     umath_kahan_add_f64

; -----------------------------------------------------------------------------
; umath_kahan_result_f32 - compensated total, rounded to float
; args:    rdi = pointer to state
; returns: xmm0 = sum as float
; -----------------------------------------------------------------------------
global umath_kahan_result_f32
umath_kahan_result_f32:
    sub     rsp, 8              ; keep rsp 16-byte aligned at the call
    call    umath_kahan_result_f64
    cvtsd2ss xmm0, xmm0
    add     rsp, 8
    ret

%endif ; GUARD_LIB_UMATH_STABILITY_KAHAN_F32_ASM
