%ifndef GUARD_LIB_UMATH_MATH_FN_SQRT_F64_ASM
%define GUARD_LIB_UMATH_MATH_FN_SQRT_F64_ASM
; =============================================================================
; umath - unified math library
; math_fn/sqrt_f64.asm - double-precision square root implementations
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; Domain:
;   - sqrtsd/sqrtpd already return NaN for negative inputs and +Inf for +Inf
;     per IEEE 754, so the exact path needs no explicit domain branch.
;   - SSE2 has no hardware reciprocal-sqrt estimate for doubles (rsqrtss/
;     rsqrtps are single-precision only). The approx/refined paths get their
;     initial estimate by round-tripping through a single-precision rsqrt:
;     cvtsd2ss -> rsqrtss -> cvtss2sd. That estimate carries only ~12 bits of
;     the ~23 a float can hold once widened, so it needs more Newton-Raphson
;     iterations than the f32 path to close in on double precision, and
;     "refined" here should still be read as an estimate, not IEEE-exact.
;
; Design & Optimization:
;   - Exact scalar/array/inplace sqrt via hardware sqrtsd/sqrtpd.
;   - Approximate sqrt: val * rsqrt_estimate(val), ~12-bit precision.
;   - Refined sqrt: two Newton-Raphson steps on the reciprocal-sqrt estimate
;     (each step roughly doubles correct bits: 12 -> 24 -> 48) before the
;     final val * y multiply.
;   - Unrolled 4x (8 doubles/iter) array loops with vector and scalar tails
;     for the exact path; the approx path works 2 doubles/iter since the
;     estimate itself is float-lane-bound.
; =============================================================================

bits 64

section .rodata
align 16
sqrtf64_half:      dq 0.5, 0.5
sqrtf64_three:     dq 3.0, 3.0

section .text

; -----------------------------------------------------------------------------
; umath_sqrt_f64 - exact scalar double-precision square root
; args:    xmm0 = input value (val)
; returns: xmm0 = sqrt(val)
; -----------------------------------------------------------------------------
global umath_sqrt_f64
umath_sqrt_f64:
    sqrtsd  xmm0, xmm0
    ret

; -----------------------------------------------------------------------------
; umath_sqrt_f64_approx - fast approximate scalar sqrt (val * rsqrt_est(val))
; args:    xmm0 = input value (val), must be > 0
; returns: xmm0 = approx(sqrt(val)) (approx 12-bit precision)
; -----------------------------------------------------------------------------
global umath_sqrt_f64_approx
umath_sqrt_f64_approx:
    cvtsd2ss xmm1, xmm0          ; xmm1 = (float)val
    rsqrtss  xmm1, xmm1          ; xmm1 = approx(1 / sqrt(val)) in float
    cvtss2sd xmm1, xmm1          ; xmm1 = widened back to double
    mulsd    xmm0, xmm1          ; xmm0 = val * approx(1 / sqrt(val))
    ret

; -----------------------------------------------------------------------------
; umath_sqrt_f64_refined - Newton-Raphson refined scalar sqrt (2 steps)
; args:    xmm0 = input value (val), must be > 0
; returns: xmm0 = refined(sqrt(val)) (approx 48-bit precision)
;
; y0 = rsqrt_est(val)                       ; float-precision initial guess
; yN+1 = yN * (1.5 - 0.5 * val * yN * yN)   ; Newton-Raphson step on 1/sqrt
; result = val * y2
; -----------------------------------------------------------------------------
global umath_sqrt_f64_refined
umath_sqrt_f64_refined:
    cvtsd2ss xmm1, xmm0
    rsqrtss  xmm1, xmm1
    cvtss2sd xmm1, xmm1          ; xmm1 = y0 (double)

    ; step 1: y1 = y0 * (1.5 - 0.5 * val * y0 * y0)
    movsd   xmm2, xmm0
    mulsd   xmm2, xmm1
    mulsd   xmm2, xmm1           ; xmm2 = val * y0 * y0
    movsd   xmm3, [rel sqrtf64_three]
    subsd   xmm3, xmm2
    mulsd   xmm3, [rel sqrtf64_half]
    mulsd   xmm1, xmm3           ; xmm1 = y1

    ; step 2: y2 = y1 * (1.5 - 0.5 * val * y1 * y1)
    movsd   xmm2, xmm0
    mulsd   xmm2, xmm1
    mulsd   xmm2, xmm1
    movsd   xmm3, [rel sqrtf64_three]
    subsd   xmm3, xmm2
    mulsd   xmm3, [rel sqrtf64_half]
    mulsd   xmm1, xmm3           ; xmm1 = y2

    mulsd   xmm0, xmm1           ; xmm0 = val * y2
    ret

; -----------------------------------------------------------------------------
; umath_sqrt_f64_array - exact sqrt of an array of doubles
; args:    rdi = destination pointer (dst)
;          rsi = source pointer (src)
;          rdx = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_sqrt_f64_array
umath_sqrt_f64_array:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done
    test    rdx, rdx
    jz      .done

    cmp     rdx, 8
    jb      .single_doubles

    mov     rcx, rdx
    shr     rcx, 3              ; count of 8-double (64-byte) blocks

.loop_unrolled:
    movups  xmm0, [rsi]
    movups  xmm1, [rsi + 16]
    movups  xmm2, [rsi + 32]
    movups  xmm3, [rsi + 48]

    sqrtpd  xmm0, xmm0
    sqrtpd  xmm1, xmm1
    sqrtpd  xmm2, xmm2
    sqrtpd  xmm3, xmm3

    movups  [rdi], xmm0
    movups  [rdi + 16], xmm1
    movups  [rdi + 32], xmm2
    movups  [rdi + 48], xmm3

    add     rsi, 64
    add     rdi, 64
    dec     rcx
    jnz     .loop_unrolled

    and     rdx, 7
    jz      .done

.single_doubles:
    cmp     rdx, 2
    jb      .residuals

    mov     rcx, rdx
    shr     rcx, 1

.loop_vector:
    movups  xmm0, [rsi]
    sqrtpd  xmm0, xmm0
    movups  [rdi], xmm0
    add     rsi, 16
    add     rdi, 16
    dec     rcx
    jnz     .loop_vector

    and     rdx, 1
    jz      .done

.residuals:
    movsd   xmm0, [rsi]
    sqrtsd  xmm0, xmm0
    movsd   [rdi], xmm0
    add     rsi, 8
    add     rdi, 8
    dec     rdx
    jnz     .residuals

.done:
    ret

; -----------------------------------------------------------------------------
; umath_sqrt_f64_array_approx - fast approximate sqrt of an array of doubles
; args:    rdi = destination pointer (dst)
;          rsi = source pointer (src), all elements must be > 0
;          rdx = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_sqrt_f64_array_approx
umath_sqrt_f64_array_approx:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done
    test    rdx, rdx
    jz      .done

.loop_pair:
    cmp     rdx, 2
    jb      .residual

    movups  xmm0, [rsi]          ; xmm0 = 2 doubles
    cvtpd2ps xmm1, xmm0          ; xmm1 = 2 floats (low qword), upper zeroed
    rsqrtps  xmm1, xmm1          ; approx 1/sqrt for all 4 lanes (only low 2 used)
    cvtps2pd xmm1, xmm1          ; xmm1 = 2 doubles widened back
    mulpd    xmm0, xmm1
    movups  [rdi], xmm0

    add     rsi, 16
    add     rdi, 16
    sub     rdx, 2
    jmp     .loop_pair

.residual:
    test    rdx, rdx
    jz      .done

    movsd   xmm0, [rsi]
    cvtsd2ss xmm1, xmm0
    rsqrtss  xmm1, xmm1
    cvtss2sd xmm1, xmm1
    mulsd    xmm0, xmm1
    movsd   [rdi], xmm0

.done:
    ret

; -----------------------------------------------------------------------------
; umath_sqrt_f64_inplace - exact in-place sqrt of a double array
; args:    rdi = buffer pointer (buf)
;          rsi = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_sqrt_f64_inplace
umath_sqrt_f64_inplace:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done

    cmp     rsi, 8
    jb      .single_doubles

    mov     rcx, rsi
    shr     rcx, 3

.loop_unrolled:
    movups  xmm0, [rdi]
    movups  xmm1, [rdi + 16]
    movups  xmm2, [rdi + 32]
    movups  xmm3, [rdi + 48]

    sqrtpd  xmm0, xmm0
    sqrtpd  xmm1, xmm1
    sqrtpd  xmm2, xmm2
    sqrtpd  xmm3, xmm3

    movups  [rdi], xmm0
    movups  [rdi + 16], xmm1
    movups  [rdi + 32], xmm2
    movups  [rdi + 48], xmm3

    add     rdi, 64
    dec     rcx
    jnz     .loop_unrolled

    and     rsi, 7
    jz      .done

.single_doubles:
    cmp     rsi, 2
    jb      .residuals

    mov     rcx, rsi
    shr     rcx, 1

.loop_vector:
    movups  xmm0, [rdi]
    sqrtpd  xmm0, xmm0
    movups  [rdi], xmm0
    add     rdi, 16
    dec     rcx
    jnz     .loop_vector

    and     rsi, 1
    jz      .done

.residuals:
    movsd   xmm0, [rdi]
    sqrtsd  xmm0, xmm0
    movsd   [rdi], xmm0
    add     rdi, 8
    dec     rsi
    jnz     .residuals

.done:
    ret

%endif ; GUARD_LIB_UMATH_MATH_FN_SQRT_F64_ASM
