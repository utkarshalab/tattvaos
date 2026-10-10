%ifndef GUARD_LIB_UMATH_STABILITY_WELFORD_F64_ASM
%define GUARD_LIB_UMATH_STABILITY_WELFORD_F64_ASM
; =============================================================================
; umath - unified math library
; stability/welford_f64.asm - numerically stable mean/variance accumulation
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; State (24 bytes, zero-filled = empty):
;
;   +----------------+----------------+----------------+
;   | count (u64)    | mean (f64)     | m2 (f64)       |
;   +----------------+----------------+----------------+
;   Offset 0         Offset 8         Offset 16
;
; m2 is the sum of squared deviations from the mean; variance = m2 / (count
; - ddof). The naive E[x^2] - E[x]^2 formula cancels catastrophically when
; the mean is large relative to the spread (and can even go negative);
; every path here works with deviations instead:
;
;   - umath_welford_push_f64: Welford's one-sample update
;       delta = x - mean; mean += delta / n; m2 += delta * (x - mean)
;   - umath_welford_update_f64: a whole array at once with the corrected
;     two-pass method (compensated mean, then sum of deviations d and of d^2,
;     m2 = sum(d^2) - sum(d)^2 / n), merged into the state.
;   - umath_welford_merge: Chan et al.'s parallel combination of two states
;       delta = mean_b - mean_a; n = n_a + n_b
;       mean = mean_a + delta * n_b / n
;       m2 = m2_a + m2_b + delta^2 * n_a * n_b / n
;     so partial results from separate chunks or threads combine exactly.
;
; NaN/Inf in the data propagate into mean and m2.
; =============================================================================

bits 64

%include "lib/umath/stability/kahan_f64.asm"

section .rodata
align 8
welff64_nan:    dq 0x7FF8000000000000

section .text

; -----------------------------------------------------------------------------
; umath_welford_init - reset a state to empty
; args:    rdi = pointer to 24-byte state
; returns: void
; -----------------------------------------------------------------------------
global umath_welford_init
umath_welford_init:
    xorps   xmm0, xmm0
    movups  [rdi], xmm0
    mov     qword [rdi + 16], 0
    ret

; -----------------------------------------------------------------------------
; umath_welford_push_f64 - add one sample
; args:    rdi = pointer to state
;          xmm0 = sample
; returns: void
; -----------------------------------------------------------------------------
global umath_welford_push_f64
umath_welford_push_f64:
    mov     rax, [rdi]
    inc     rax
    mov     [rdi], rax
    cvtsi2sd xmm1, rax          ; n (counts stay far below 2^53)
    movsd   xmm2, xmm0
    subsd   xmm2, [rdi + 8]     ; delta = x - mean
    movsd   xmm3, xmm2
    divsd   xmm3, xmm1
    addsd   xmm3, [rdi + 8]     ; mean += delta / n
    movsd   [rdi + 8], xmm3
    subsd   xmm0, xmm3          ; x - new mean
    mulsd   xmm0, xmm2
    addsd   xmm0, [rdi + 16]    ; m2 += delta * (x - new mean)
    movsd   [rdi + 16], xmm0
    ret

; -----------------------------------------------------------------------------
; welfordf64__merge_raw - internal: merge (count, mean, m2) into a state
; args:    rdi = pointer to state
;          rsi = count_b, xmm0 = mean_b, xmm1 = m2_b
; returns: void
; Clobbers rax, rcx, xmm2-xmm7. Not declared global.
; -----------------------------------------------------------------------------
welfordf64__merge_raw:
    test    rsi, rsi
    jz      .done               ; nothing to add
    mov     rax, [rdi]
    test    rax, rax
    jnz     .combine
    mov     [rdi], rsi          ; empty state: take b as is
    movsd   [rdi + 8], xmm0
    movsd   [rdi + 16], xmm1
    ret
.combine:
    lea     rcx, [rax + rsi]
    mov     [rdi], rcx
    cvtsi2sd xmm2, rax          ; n_a
    cvtsi2sd xmm3, rsi          ; n_b
    cvtsi2sd xmm4, rcx          ; n
    movsd   xmm5, xmm0
    subsd   xmm5, [rdi + 8]     ; delta = mean_b - mean_a
    movsd   xmm6, xmm5
    mulsd   xmm6, xmm3
    divsd   xmm6, xmm4
    addsd   xmm6, [rdi + 8]     ; mean = mean_a + delta * n_b / n
    movsd   [rdi + 8], xmm6
    mulsd   xmm5, xmm5          ; delta^2
    divsd   xmm2, xmm4
    mulsd   xmm5, xmm2
    mulsd   xmm5, xmm3          ; delta^2 * (n_a / n) * n_b
    addsd   xmm5, xmm1
    addsd   xmm5, [rdi + 16]    ; m2 = m2_a + m2_b + ...
    movsd   [rdi + 16], xmm5
.done:
    ret

; -----------------------------------------------------------------------------
; umath_welford_merge - merge state b into state a (a = a combined with b)
; args:    rdi = pointer to state a (updated)
;          rsi = pointer to state b (unchanged)
; returns: void
; -----------------------------------------------------------------------------
global umath_welford_merge
umath_welford_merge:
    movsd   xmm0, [rsi + 8]
    movsd   xmm1, [rsi + 16]
    mov     rsi, [rsi]
    jmp     welfordf64__merge_raw

; -----------------------------------------------------------------------------
; welfordf64__finish_batch - internal: turn two-pass sums into (mean, m2)
;          and merge them into a state
; args:    rdi = pointer to state, rsi = count (> 0)
;          xmm0 = first-pass mean, xmm3 = sum(d), xmm4 = sum(d^2)
; returns: void
; -----------------------------------------------------------------------------
welfordf64__finish_batch:
    cvtsi2sd xmm1, rsi          ; n
    movsd   xmm5, xmm3
    divsd   xmm5, xmm1          ; sum(d) / n
    addsd   xmm0, xmm5          ; corrected mean
    mulsd   xmm5, xmm3          ; sum(d)^2 / n
    movsd   xmm1, xmm4
    subsd   xmm1, xmm5          ; m2 = sum(d^2) - sum(d)^2 / n
    xorpd   xmm7, xmm7
    maxsd   xmm7, xmm1          ; clamp rounding below 0; NaN m2 passes through
    movapd  xmm1, xmm7
    jmp     welfordf64__merge_raw

; -----------------------------------------------------------------------------
; umath_welford_update_f64 - add an array of samples
; args:    rdi = pointer to state
;          rsi = source pointer (src)
;          rdx = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_welford_update_f64
umath_welford_update_f64:
    test    rsi, rsi
    jz      .done
    test    rdx, rdx
    jz      .done
    push    rbx
    push    r12
    push    r13                 ; 3 pushes: rsp 16-byte aligned at the calls
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx

    mov     rdi, r12
    mov     rsi, r13
    call    umath_kahan_sum_f64 ; xmm0 = sum
    cvtsi2sd xmm1, r13
    divsd   xmm0, xmm1          ; first-pass mean

    movapd  xmm2, xmm0
    unpcklpd xmm2, xmm2         ; mean in both lanes
    xorpd   xmm3, xmm3          ; sum(d) lanes
    xorpd   xmm4, xmm4          ; sum(d^2) lanes
    mov     rsi, r12
    mov     rcx, r13
    shr     rcx, 1
    jz      .tail
.loop2:
    movupd  xmm5, [rsi]
    subpd   xmm5, xmm2          ; d
    addpd   xmm3, xmm5
    mulpd   xmm5, xmm5
    addpd   xmm4, xmm5
    add     rsi, 16
    dec     rcx
    jnz     .loop2
.tail:
    movapd  xmm5, xmm3
    unpckhpd xmm5, xmm5
    addsd   xmm3, xmm5          ; sum(d)
    movapd  xmm5, xmm4
    unpckhpd xmm5, xmm5
    addsd   xmm4, xmm5          ; sum(d^2)
    test    r13, 1
    jz      .merge
    movsd   xmm5, [rsi]
    subsd   xmm5, xmm2
    addsd   xmm3, xmm5
    mulsd   xmm5, xmm5
    addsd   xmm4, xmm5
.merge:
    mov     rdi, rbx
    mov     rsi, r13
    call    welfordf64__finish_batch
    pop     r13
    pop     r12
    pop     rbx
.done:
    ret

; -----------------------------------------------------------------------------
; umath_welford_count - number of samples
; args:    rdi = pointer to state
; returns: rax = count
; -----------------------------------------------------------------------------
global umath_welford_count
umath_welford_count:
    mov     rax, [rdi]
    ret

; -----------------------------------------------------------------------------
; umath_welford_mean - mean of the samples
; args:    rdi = pointer to state
; returns: xmm0 = mean (NaN for an empty state)
; -----------------------------------------------------------------------------
global umath_welford_mean
umath_welford_mean:
    cmp     qword [rdi], 0
    je      .nan
    movsd   xmm0, [rdi + 8]
    ret
.nan:
    movsd   xmm0, [rel welff64_nan]
    ret

; -----------------------------------------------------------------------------
; umath_welford_variance - variance with ddof degrees of freedom removed
; args:    rdi = pointer to state
;          rsi = ddof (0 = population variance, 1 = sample variance)
; returns: xmm0 = m2 / (count - ddof) (NaN if count <= ddof)
; -----------------------------------------------------------------------------
global umath_welford_variance
umath_welford_variance:
    mov     rax, [rdi]
    cmp     rax, rsi
    jbe     .nan
    sub     rax, rsi
    cvtsi2sd xmm1, rax
    movsd   xmm0, [rdi + 16]
    divsd   xmm0, xmm1
    ret
.nan:
    movsd   xmm0, [rel welff64_nan]
    ret

%endif ; GUARD_LIB_UMATH_STABILITY_WELFORD_F64_ASM
