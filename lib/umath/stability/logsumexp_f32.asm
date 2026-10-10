%ifndef GUARD_LIB_UMATH_STABILITY_LOGSUMEXP_F32_ASM
%define GUARD_LIB_UMATH_STABILITY_LOGSUMEXP_F32_ASM
; =============================================================================
; umath - unified math library
; stability/logsumexp_f32.asm - log(sum(exp(x))) of float data
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; Same algorithm and special values as logsumexp_f64.asm, evaluated in
; double: each float is widened exactly, the max shift, exp, compensated sum
; and log run in double, and the result is rounded to float once. float's
; own exp/log would add a few float ULP per term; this way the result is
; within an ULP of the exact value.
; =============================================================================

bits 64

%include "lib/umath/stability/logsumexp_f64.asm"

section .text

; -----------------------------------------------------------------------------
; umath_logsumexp_f32 - log of the sum of exponentials of a float array
; args:    rdi = source pointer (src)
;          rsi = size of array (count)
; returns: xmm0 = log(sum(exp(src[i]))) as float
; -----------------------------------------------------------------------------
global umath_logsumexp_f32
umath_logsumexp_f32:
    movsd   xmm0, [rel lsef64_neg_inf]
    test    rdi, rdi
    jz      .narrow
    test    rsi, rsi
    jz      .narrow

    ; pass 1: maximum (in double), returning NaN as soon as one is seen
    mov     rax, rdi
    mov     rcx, rsi
.max_loop:
    cvtss2sd xmm1, [rax]
    ucomisd xmm1, xmm1
    jp      .nan
    maxsd   xmm0, xmm1
    add     rax, 4
    dec     rcx
    jnz     .max_loop

    ucomisd xmm0, [rel lsef64_pos_inf]
    je      .narrow             ; +Inf dominates
    ucomisd xmm0, [rel lsef64_neg_inf]
    je      .narrow             ; every element is -Inf

    ; pass 2: compensated sum of exp(x - m)
    push    rbx
    push    r12
    push    r13                 ; 3 pushes + 32 bytes: rsp 16-aligned at calls
    sub     rsp, 32             ; [rsp] = kahan state, [rsp + 16] = m
    mov     rbx, rdi
    mov     r12, rsi
    movsd   [rsp + 16], xmm0
    mov     rdi, rsp
    call    umath_kahan_init_f64
.exp_loop:
    cvtss2sd xmm0, [rbx]
    subsd   xmm0, [rsp + 16]
    call    umath_exp_f64
    mov     rdi, rsp
    call    umath_kahan_add_f64
    add     rbx, 4
    dec     r12
    jnz     .exp_loop

    mov     rdi, rsp
    call    umath_kahan_result_f64
    call    umath_log_f64
    addsd   xmm0, [rsp + 16]
    add     rsp, 32
    pop     r13
    pop     r12
    pop     rbx
.narrow:
    cvtsd2ss xmm0, xmm0         ; single rounding to float
    ret
.nan:
    movsd   xmm0, [rel lsef64_nan]
    jmp     .narrow

%endif ; GUARD_LIB_UMATH_STABILITY_LOGSUMEXP_F32_ASM
