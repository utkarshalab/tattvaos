%ifndef GUARD_LIB_UMATH_STABILITY_LOGSUMEXP_F64_ASM
%define GUARD_LIB_UMATH_STABILITY_LOGSUMEXP_F64_ASM
; =============================================================================
; umath - unified math library
; stability/logsumexp_f64.asm - log(sum(exp(x))) without overflow, double
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; Algorithm: with m = max(x),
;
;     logsumexp(x) = m + log(sum(exp(x_i - m)))
;
; Every exp argument is <= 0, so no term overflows, and the largest term is
; exactly 1, so the sum is in [1, n] and its log never underflows to -Inf
; the way log(sum(exp(x))) does for very negative inputs. This is the
; building block for a stable softmax: softmax_i = exp(x_i - logsumexp(x)).
;
; Both passes are packed, two lanes at a time:
;   1. max with maxpd, NaN tracked separately (cmpunordpd) so a NaN anywhere
;      returns NaN;
;   2. exp(x - m) through exp_f64.asm's two-lane core
;      (umath_exp_f64__reduce2, bit-identical to umath_exp_f64), summed with
;      the packed Neumaier step from kahan_f64.asm; the lanes are folded with
;      the same compensated step at the end.
;
; Special values:
;   - empty or NULL array        -> -Inf (log of an empty sum)
;   - any NaN                    -> NaN
;   - max is +Inf                -> +Inf
;   - every element is -Inf      -> -Inf
; =============================================================================

bits 64

%include "lib/umath/math_fn/exp_f64.asm"
%include "lib/umath/math_fn/log_f64.asm"
%include "lib/umath/stability/kahan_f64.asm"

section .rodata
align 16
lsef64_neg_inf:     dq 0xFFF0000000000000, 0xFFF0000000000000
lsef64_pos_inf:     dq 0x7FF0000000000000
lsef64_nan:         dq 0x7FF8000000000000

section .text

; -----------------------------------------------------------------------------
; umath_logsumexp_f64 - log of the sum of exponentials of an array
; args:    rdi = source pointer (src)
;          rsi = size of array (count)
; returns: xmm0 = log(sum(exp(src[i])))
; -----------------------------------------------------------------------------
global umath_logsumexp_f64
umath_logsumexp_f64:
    movsd   xmm0, [rel lsef64_neg_inf]
    test    rdi, rdi
    jz      .ret
    test    rsi, rsi
    jz      .ret

    ; pass 1: maximum, with a NaN flag on the side
    movapd  xmm1, [rel lsef64_neg_inf]  ; running max, two lanes
    xorpd   xmm2, xmm2                  ; NaN lanes seen
    mov     rax, rdi
    mov     rcx, rsi
    shr     rcx, 1
    jz      .max_fold
.max_loop:
    movupd  xmm3, [rax]
    movapd  xmm4, xmm3
    cmpunordpd xmm4, xmm3
    orpd    xmm2, xmm4
    maxpd   xmm1, xmm3
    add     rax, 16
    dec     rcx
    jnz     .max_loop
.max_fold:
    movmskpd ecx, xmm2
    test    ecx, ecx
    jnz     .nan
    movapd  xmm0, xmm1
    unpckhpd xmm1, xmm1
    maxsd   xmm0, xmm1
    test    rsi, 1
    jz      .have_max
    movsd   xmm1, [rax]                 ; odd element
    ucomisd xmm1, xmm1
    jp      .nan
    maxsd   xmm0, xmm1
.have_max:
    ucomisd xmm0, [rel lsef64_pos_inf]
    je      .ret                ; +Inf dominates
    ucomisd xmm0, [rel lsef64_neg_inf]
    je      .ret                ; every element is -Inf

    ; pass 2: compensated sum of exp(x - m), two lanes
    sub     rsp, 24             ; [rsp] = m; rsp 16-aligned at the calls
    movsd   [rsp], xmm0
    movapd  xmm12, xmm0
    unpcklpd xmm12, xmm12       ; m in both lanes
    xorpd   xmm10, xmm10        ; s lanes
    xorpd   xmm11, xmm11        ; c lanes
    movapd  xmm15, [rel kahanf64_abs_mask]
    mov     rax, rdi
    mov     rcx, rsi
    shr     rcx, 1
    jz      .fold
.exp_loop:
    movupd  xmm0, [rax]
    subpd   xmm0, xmm12
    call    umath_exp_f64__reduce2  ; xmm0-xmm4 only, no GPRs
    kahanf64_step_pd xmm10, xmm11, xmm0, xmm5, xmm6, xmm7
    add     rax, 16
    dec     rcx
    jnz     .exp_loop
.fold:
    movapd  xmm8, xmm10
    unpckhpd xmm8, xmm8         ; s lane 1
    movapd  xmm9, xmm11
    unpckhpd xmm9, xmm9
    addsd   xmm11, xmm9         ; c = c lane 0 + c lane 1
    kahanf64_step_sd xmm10, xmm11, xmm8, xmm5, xmm6, xmm7
    test    rsi, 1
    jz      .finish
    movsd   xmm0, [rax]         ; odd element
    subsd   xmm0, [rsp]
    call    umath_exp_f64       ; rax/rcx, xmm1-xmm4
    movapd  xmm15, [rel kahanf64_abs_mask]
    kahanf64_step_sd xmm10, xmm11, xmm0, xmm5, xmm6, xmm7
.finish:
    movapd  xmm0, xmm10
    movapd  xmm1, xmm11
    call    kahanf64__finish    ; sum in [1, n]
    call    umath_log_f64
    addsd   xmm0, [rsp]         ; m + log(sum)
    add     rsp, 24
.ret:
    ret
.nan:
    movsd   xmm0, [rel lsef64_nan]
    ret

%endif ; GUARD_LIB_UMATH_STABILITY_LOGSUMEXP_F64_ASM
