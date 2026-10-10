%ifndef GUARD_LIB_UMATH_STABILITY_WELFORD_F32_ASM
%define GUARD_LIB_UMATH_STABILITY_WELFORD_F32_ASM
; =============================================================================
; umath - unified math library
; stability/welford_f32.asm - mean/variance accumulation of float samples
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; Float samples feed the same double-precision state as welford_f64.asm
; (see that file for the layout and the algorithms); samples are widened
; exactly with cvtss2sd/cvtps2pd, so float and double samples can be mixed
; in one state and read back with umath_welford_mean/variance (f64).
; =============================================================================

bits 64

%include "lib/umath/stability/welford_f64.asm"

section .text

; -----------------------------------------------------------------------------
; umath_welford_push_f32 - add one float sample
; args:    rdi = pointer to state
;          xmm0 = sample (float)
; returns: void
; -----------------------------------------------------------------------------
global umath_welford_push_f32
umath_welford_push_f32:
    cvtss2sd xmm0, xmm0
    jmp     umath_welford_push_f64

; -----------------------------------------------------------------------------
; umath_welford_update_f32 - add an array of float samples
; args:    rdi = pointer to state
;          rsi = source pointer (src)
;          rdx = size of array (count)
; returns: void
;
; Corrected two-pass, in double: pass 1 sums the widened samples (a plain
; double sum is accurate to ~n * 2^-53 relative, and the second pass
; corrects the mean to first order anyway), pass 2 sums d and d^2.
; -----------------------------------------------------------------------------
global umath_welford_update_f32
umath_welford_update_f32:
    test    rsi, rsi
    jz      .done
    test    rdx, rdx
    jz      .done

    ; pass 1: sum in double, two lanes
    xorpd   xmm0, xmm0
    mov     r8, rsi
    mov     rcx, rdx
    shr     rcx, 1
    jz      .sum_tail
.sum_loop:
    cvtps2pd xmm5, [r8]
    addpd   xmm0, xmm5
    add     r8, 8
    dec     rcx
    jnz     .sum_loop
.sum_tail:
    movapd  xmm5, xmm0
    unpckhpd xmm5, xmm5
    addsd   xmm0, xmm5
    test    rdx, 1
    jz      .mean
    cvtss2sd xmm5, [r8]
    addsd   xmm0, xmm5
.mean:
    cvtsi2sd xmm1, rdx
    divsd   xmm0, xmm1          ; first-pass mean

    ; pass 2: sum(d) and sum(d^2), two lanes
    movapd  xmm2, xmm0
    unpcklpd xmm2, xmm2
    xorpd   xmm3, xmm3
    xorpd   xmm4, xmm4
    mov     r8, rsi
    mov     rcx, rdx
    shr     rcx, 1
    jz      .dev_tail
.dev_loop:
    cvtps2pd xmm5, [r8]
    subpd   xmm5, xmm2
    addpd   xmm3, xmm5
    mulpd   xmm5, xmm5
    addpd   xmm4, xmm5
    add     r8, 8
    dec     rcx
    jnz     .dev_loop
.dev_tail:
    movapd  xmm5, xmm3
    unpckhpd xmm5, xmm5
    addsd   xmm3, xmm5
    movapd  xmm5, xmm4
    unpckhpd xmm5, xmm5
    addsd   xmm4, xmm5
    test    rdx, 1
    jz      .merge
    cvtss2sd xmm5, [r8]
    subsd   xmm5, xmm2
    addsd   xmm3, xmm5
    mulsd   xmm5, xmm5
    addsd   xmm4, xmm5
.merge:
    mov     rsi, rdx
    jmp     welfordf64__finish_batch
.done:
    ret

%endif ; GUARD_LIB_UMATH_STABILITY_WELFORD_F32_ASM
