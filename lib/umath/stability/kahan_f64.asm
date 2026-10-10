%ifndef GUARD_LIB_UMATH_STABILITY_KAHAN_F64_ASM
%define GUARD_LIB_UMATH_STABILITY_KAHAN_F64_ASM
; =============================================================================
; umath - unified math library
; stability/kahan_f64.asm - compensated (Neumaier) summation, double precision
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; Algorithm: Neumaier's variant of Kahan summation. For each addend x:
;
;     t = s + x
;     c += (|s| >= |x|) ? (s - t) + x : (x - t) + s
;     s = t
;
; and the result is s + c. The correction term recovers exactly the low
; bits that each addition rounded away, so the error no longer grows with
; the number of terms: the result is within about 2 ULP of the exact sum
; plus a term proportional to eps^2 * sum(|x|). Plain Kahan picks the
; first branch unconditionally and loses the correction whenever an addend
; is larger than the running sum; Neumaier's comparison fixes that.
;
; Non-finite input: the correction is meaningless once s is +/-Inf or NaN
; (Inf - Inf = NaN would poison c), so the result is s alone whenever s is
; not finite: an Inf addend gives Inf, Inf + -Inf or any NaN gives NaN.
;
; Design & Optimization:
;   - umath_kahan_sum_f64 keeps four independent (s, c) lanes in two xmm
;     registers, processes 4 doubles per iteration with a branch-free
;     packed Neumaier step (cmplepd mask + and/andn/or blend), then folds
;     the lanes together with the same compensated step.
;   - umath_kahan_init/add/result_f64 expose the same accumulator as a
;     16-byte state ({ f64 sum, f64 comp }) for streaming use.
; =============================================================================

bits 64

section .rodata
align 16
kahanf64_abs_mask:  dq 0x7FFFFFFFFFFFFFFF, 0x7FFFFFFFFFFFFFFF
kahanf64_pos_inf:   dq 0x7FF0000000000000

section .text

; -----------------------------------------------------------------------------
; kahanf64_step_pd - packed Neumaier step on two double lanes
; args:    %1 = s (in/out), %2 = c (in/out), %3 = x (clobbered)
;          %4, %5, %6 = scratch registers
; expects: xmm15 = absolute-value mask
; -----------------------------------------------------------------------------
%macro kahanf64_step_pd 6
    movapd  %4, %1
    addpd   %4, %3              ; %4 = t = s + x
    movapd  %5, %1
    andpd   %5, xmm15           ; |s|
    movapd  %6, %3
    andpd   %6, xmm15           ; |x|
    cmplepd %6, %5              ; %6 = mask: |x| <= |s|
    movapd  %5, %1
    subpd   %5, %4
    addpd   %5, %3              ; %5 = (s - t) + x
    subpd   %3, %4
    addpd   %3, %1              ; %3 = (x - t) + s
    andpd   %5, %6
    andnpd  %6, %3
    orpd    %5, %6              ; pick the branch per lane
    addpd   %2, %5              ; c += correction
    movapd  %1, %4              ; s = t
%endmacro

; -----------------------------------------------------------------------------
; kahanf64_step_sd - scalar Neumaier step (low lane only)
; args:    %1 = s (in/out), %2 = c (in/out), %3 = x (clobbered)
;          %4, %5, %6 = scratch registers
; expects: xmm15 = absolute-value mask
; -----------------------------------------------------------------------------
%macro kahanf64_step_sd 6
    movapd  %4, %1
    addsd   %4, %3              ; %4 = t = s + x
    movapd  %5, %1
    andpd   %5, xmm15           ; |s|
    movapd  %6, %3
    andpd   %6, xmm15           ; |x|
    cmplesd %6, %5              ; %6 = mask: |x| <= |s|
    movapd  %5, %1
    subsd   %5, %4
    addsd   %5, %3              ; %5 = (s - t) + x
    subsd   %3, %4
    addsd   %3, %1              ; %3 = (x - t) + s
    andpd   %5, %6
    andnpd  %6, %3
    orpd    %5, %6
    addsd   %2, %5              ; c += correction
    movapd  %1, %4              ; s = t
%endmacro

; -----------------------------------------------------------------------------
; kahanf64__finish - internal: xmm0 = s + c if s is finite, else s
; args:    xmm0 = s, xmm1 = c
; returns: xmm0 = compensated result
; Clobbers xmm2.
; -----------------------------------------------------------------------------
kahanf64__finish:
    movapd  xmm2, xmm0
    andpd   xmm2, [rel kahanf64_abs_mask]
    ucomisd xmm2, [rel kahanf64_pos_inf]
    jae     .done               ; +/-Inf, or NaN (unordered sets CF)
    jp      .done
    addsd   xmm0, xmm1
.done:
    ret

; -----------------------------------------------------------------------------
; umath_kahan_sum_f64 - compensated sum of an array of doubles
; args:    rdi = source pointer (src)
;          rsi = size of array (count)
; returns: xmm0 = sum (0.0 for an empty or NULL array)
; -----------------------------------------------------------------------------
global umath_kahan_sum_f64
umath_kahan_sum_f64:
    xorpd   xmm0, xmm0          ; s lanes 0-1
    xorpd   xmm1, xmm1          ; c lanes 0-1
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done

    xorpd   xmm2, xmm2          ; s lanes 2-3
    xorpd   xmm3, xmm3          ; c lanes 2-3
    movapd  xmm15, [rel kahanf64_abs_mask]

    mov     rcx, rsi
    shr     rcx, 2              ; count of 4-double blocks
    jz      .fold

.loop4:
    movupd  xmm4, [rdi]
    movupd  xmm5, [rdi + 16]
    kahanf64_step_pd xmm0, xmm1, xmm4, xmm6, xmm7, xmm8
    kahanf64_step_pd xmm2, xmm3, xmm5, xmm9, xmm10, xmm11
    add     rdi, 32
    dec     rcx
    jnz     .loop4

.fold:
    ; lanes 2-3 into lanes 0-1, then lane 1 into lane 0
    addpd   xmm1, xmm3
    kahanf64_step_pd xmm0, xmm1, xmm2, xmm6, xmm7, xmm8
    movapd  xmm4, xmm0
    unpckhpd xmm4, xmm4         ; xmm4 = s lane 1
    movapd  xmm5, xmm1
    unpckhpd xmm5, xmm5
    addsd   xmm1, xmm5          ; c = c lane 0 + c lane 1
    kahanf64_step_sd xmm0, xmm1, xmm4, xmm6, xmm7, xmm8

    and     rsi, 3
    jz      .finish
.tail:
    movsd   xmm4, [rdi]
    kahanf64_step_sd xmm0, xmm1, xmm4, xmm6, xmm7, xmm8
    add     rdi, 8
    dec     rsi
    jnz     .tail

.finish:
    jmp     kahanf64__finish
.done:
    ret

; -----------------------------------------------------------------------------
; umath_kahan_init_f64 - reset a streaming accumulator
; args:    rdi = pointer to 16-byte state { f64 sum, f64 comp }
; returns: void
; A zero-filled state is also a valid empty accumulator.
; -----------------------------------------------------------------------------
global umath_kahan_init_f64
umath_kahan_init_f64:
    xorpd   xmm0, xmm0
    movupd  [rdi], xmm0
    ret

; -----------------------------------------------------------------------------
; umath_kahan_add_f64 - add one value to a streaming accumulator
; args:    rdi = pointer to state
;          xmm0 = value to add
; returns: void
; -----------------------------------------------------------------------------
global umath_kahan_add_f64
umath_kahan_add_f64:
    movapd  xmm4, xmm0
    movsd   xmm0, [rdi]         ; s
    movsd   xmm1, [rdi + 8]     ; c
    movapd  xmm15, [rel kahanf64_abs_mask]
    kahanf64_step_sd xmm0, xmm1, xmm4, xmm5, xmm6, xmm7
    movsd   [rdi], xmm0
    movsd   [rdi + 8], xmm1
    ret

; -----------------------------------------------------------------------------
; umath_kahan_result_f64 - compensated total of a streaming accumulator
; args:    rdi = pointer to state
; returns: xmm0 = sum + comp (or sum alone if it is not finite)
; -----------------------------------------------------------------------------
global umath_kahan_result_f64
umath_kahan_result_f64:
    movsd   xmm0, [rdi]
    movsd   xmm1, [rdi + 8]
    jmp     kahanf64__finish

%endif ; GUARD_LIB_UMATH_STABILITY_KAHAN_F64_ASM
