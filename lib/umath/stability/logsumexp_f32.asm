%ifndef GUARD_LIB_UMATH_STABILITY_LOGSUMEXP_F32_ASM
%define GUARD_LIB_UMATH_STABILITY_LOGSUMEXP_F32_ASM
; =============================================================================
; umath - unified math library
; stability/logsumexp_f32.asm - log(sum(exp(x))) of float data
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; Same algorithm and special values as logsumexp_f64.asm, evaluated in
; double: the max is found on the floats (four lanes, exact), then pairs of
; floats are widened exactly and the shift, exp (exp_f64's two-lane core),
; compensated sum and log run in double; the result is rounded to float
; once. float's own exp/log would add a few float ULP per term; this way
; the result is within an ULP of the exact value.
; =============================================================================

bits 64

%include "lib/umath/stability/logsumexp_f64.asm"

section .rodata
align 16
lsef32_neg_inf4:    times 4 dd 0xFF800000

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

    ; pass 1: maximum of the floats (four lanes), NaN flag on the side
    movaps  xmm1, [rel lsef32_neg_inf4]
    xorps   xmm2, xmm2
    mov     rax, rdi
    mov     rcx, rsi
    shr     rcx, 2
    jz      .max_fold
.max_loop:
    movups  xmm3, [rax]
    movaps  xmm4, xmm3
    cmpunordps xmm4, xmm3
    orps    xmm2, xmm4
    maxps   xmm1, xmm3
    add     rax, 16
    dec     rcx
    jnz     .max_loop
.max_fold:
    movmskps ecx, xmm2
    test    ecx, ecx
    jnz     .nan
    movhlps xmm3, xmm1
    maxps   xmm1, xmm3
    movaps  xmm3, xmm1
    shufps  xmm3, xmm3, 0x55
    maxss   xmm1, xmm3          ; float max of the 4-lane part
    mov     rcx, rsi
    and     rcx, 3
    jz      .widen_max
.max_tail:
    movss   xmm3, [rax]
    ucomiss xmm3, xmm3
    jp      .nan
    maxss   xmm1, xmm3
    add     rax, 4
    dec     rcx
    jnz     .max_tail
.widen_max:
    cvtss2sd xmm0, xmm1         ; m (exact)
    ucomisd xmm0, [rel lsef64_pos_inf]
    je      .narrow             ; +Inf dominates
    ucomisd xmm0, [rel lsef64_neg_inf]
    je      .narrow             ; every element is -Inf

    ; pass 2: compensated sum of exp(x - m) in double, two lanes
    sub     rsp, 24             ; [rsp] = m; rsp 16-aligned at the calls
    movsd   [rsp], xmm0
    movapd  xmm12, xmm0
    unpcklpd xmm12, xmm12
    xorpd   xmm10, xmm10        ; s lanes
    xorpd   xmm11, xmm11        ; c lanes
    movapd  xmm15, [rel kahanf64_abs_mask]
    mov     rax, rdi
    mov     rcx, rsi
    shr     rcx, 1
    jz      .fold
.exp_loop:
    cvtps2pd xmm0, [rax]        ; two floats widened (exact)
    subpd   xmm0, xmm12
    call    umath_exp_f64__reduce2  ; xmm0-xmm4 only, no GPRs
    kahanf64_step_pd xmm10, xmm11, xmm0, xmm5, xmm6, xmm7
    add     rax, 8
    dec     rcx
    jnz     .exp_loop
.fold:
    movapd  xmm8, xmm10
    unpckhpd xmm8, xmm8
    movapd  xmm9, xmm11
    unpckhpd xmm9, xmm9
    addsd   xmm11, xmm9
    kahanf64_step_sd xmm10, xmm11, xmm8, xmm5, xmm6, xmm7
    test    rsi, 1
    jz      .finish
    cvtss2sd xmm0, [rax]        ; odd element
    subsd   xmm0, [rsp]
    call    umath_exp_f64       ; rax/rcx, xmm1-xmm4
    movapd  xmm15, [rel kahanf64_abs_mask]
    kahanf64_step_sd xmm10, xmm11, xmm0, xmm5, xmm6, xmm7
.finish:
    movapd  xmm0, xmm10
    movapd  xmm1, xmm11
    call    kahanf64__finish
    call    umath_log_f64
    addsd   xmm0, [rsp]
    add     rsp, 24
.narrow:
    cvtsd2ss xmm0, xmm0         ; single rounding to float
    ret
.nan:
    movsd   xmm0, [rel lsef64_nan]
    jmp     .narrow

%endif ; GUARD_LIB_UMATH_STABILITY_LOGSUMEXP_F32_ASM
