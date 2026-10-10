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
; the way log(sum(exp(x))) does for very negative inputs. The exp terms are
; summed with the compensated accumulator from kahan_f64.asm. This is the
; building block for a stable softmax: softmax_i = exp(x_i - logsumexp(x)).
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
align 8
lsef64_neg_inf:     dq 0xFFF0000000000000
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

    ; pass 1: maximum, returning NaN as soon as one is seen
    mov     rax, rdi
    mov     rcx, rsi
.max_loop:
    movsd   xmm1, [rax]
    ucomisd xmm1, xmm1
    jp      .nan
    maxsd   xmm0, xmm1
    add     rax, 8
    dec     rcx
    jnz     .max_loop

    ucomisd xmm0, [rel lsef64_pos_inf]
    je      .ret                ; +Inf dominates
    ucomisd xmm0, [rel lsef64_neg_inf]
    je      .ret                ; every element is -Inf

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
    movsd   xmm0, [rbx]
    subsd   xmm0, [rsp + 16]
    call    umath_exp_f64
    mov     rdi, rsp
    call    umath_kahan_add_f64
    add     rbx, 8
    dec     r12
    jnz     .exp_loop

    mov     rdi, rsp
    call    umath_kahan_result_f64  ; sum in [1, n]
    call    umath_log_f64
    addsd   xmm0, [rsp + 16]        ; m + log(sum)
    add     rsp, 32
    pop     r13
    pop     r12
    pop     rbx
.ret:
    ret
.nan:
    movsd   xmm0, [rel lsef64_nan]
    ret

%endif ; GUARD_LIB_UMATH_STABILITY_LOGSUMEXP_F64_ASM
