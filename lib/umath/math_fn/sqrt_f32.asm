%ifndef GUARD_LIB_UMATH_MATH_FN_SQRT_F32_ASM
%define GUARD_LIB_UMATH_MATH_FN_SQRT_F32_ASM
; =============================================================================
; umath - unified math library
; math_fn/sqrt_f32.asm - single-precision square root implementations
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; Domain:
;   - sqrtss/sqrtps already return NaN for negative inputs and +Inf for +Inf
;     per IEEE 754, so no explicit domain branch is needed for the exact path.
;   - The approximate/refined paths go through rsqrtss/rsqrtps (reciprocal
;     sqrt estimate), which is only defined for x > 0; callers on the approx
;     paths are expected to pre-filter non-positive input the same way they
;     would for a reciprocal.
;
; Design & Optimization:
;   - Exact scalar/array/inplace sqrt via hardware sqrtss/sqrtps.
;   - Fast approximate sqrt: x * rsqrt(x), ~12-bit precision, no division.
;   - Newton-Raphson refined sqrt (1 step) for ~23-bit precision without the
;     latency of a full hardware divide/sqrt.
;   - Unrolled 4x (16 floats/iter) array loops with vector and scalar tails.
; =============================================================================

bits 64

section .rodata
align 16
sqrtf32_half:     dd 0.5, 0.5, 0.5, 0.5
sqrtf32_three:    dd 3.0, 3.0, 3.0, 3.0

section .text

; -----------------------------------------------------------------------------
; umath_sqrt_f32 - exact scalar single-precision square root
; args:    xmm0 = input value (val)
; returns: xmm0 = sqrt(val)
; -----------------------------------------------------------------------------
global umath_sqrt_f32
umath_sqrt_f32:
    sqrtss  xmm0, xmm0
    ret

; -----------------------------------------------------------------------------
; umath_sqrt_f32_approx - fast approximate scalar sqrt (val * rsqrt(val))
; args:    xmm0 = input value (val), must be > 0
; returns: xmm0 = approx(sqrt(val)) (approx 12-bit precision)
; -----------------------------------------------------------------------------
global umath_sqrt_f32_approx
umath_sqrt_f32_approx:
    rsqrtss xmm1, xmm0          ; xmm1 = approx(1 / sqrt(val))
    mulss   xmm0, xmm1          ; xmm0 = val * approx(1 / sqrt(val))
    ret

; -----------------------------------------------------------------------------
; umath_sqrt_f32_refined - Newton-Raphson refined scalar sqrt
; args:    xmm0 = input value (val), must be > 0
; returns: xmm0 = refined(sqrt(val)) (approx 23-bit precision)
;
; y0 = rsqrt(val)                          ; initial estimate of 1/sqrt(val)
; y1 = y0 * (1.5 - 0.5 * val * y0 * y0)    ; one Newton-Raphson step on 1/sqrt
; result = val * y1                        ; sqrt(val) = val * (1/sqrt(val))
; -----------------------------------------------------------------------------
global umath_sqrt_f32_refined
umath_sqrt_f32_refined:
    rsqrtss xmm1, xmm0          ; xmm1 = y0
    movss   xmm2, xmm0          ; xmm2 = val
    mulss   xmm2, xmm1
    mulss   xmm2, xmm1          ; xmm2 = val * y0 * y0
    movss   xmm3, [rel sqrtf32_three]
    subss   xmm3, xmm2          ; xmm3 = 3.0 - val * y0 * y0
    mulss   xmm3, [rel sqrtf32_half] ; xmm3 = 0.5 * (3.0 - val * y0 * y0)
    mulss   xmm1, xmm3          ; xmm1 = y0 * 0.5 * (3.0 - val * y0 * y0) = y1
    mulss   xmm0, xmm1          ; xmm0 = val * y1
    ret

; -----------------------------------------------------------------------------
; umath_sqrt_f32_array - exact sqrt of an array of floats
; args:    rdi = destination pointer (dst)
;          rsi = source pointer (src)
;          rdx = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_sqrt_f32_array
umath_sqrt_f32_array:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done
    test    rdx, rdx
    jz      .done

    cmp     rdx, 16
    jb      .single_floats

    mov     rcx, rdx
    shr     rcx, 4              ; count of 16-float blocks

.loop_unrolled:
    movups  xmm0, [rsi]
    movups  xmm1, [rsi + 16]
    movups  xmm2, [rsi + 32]
    movups  xmm3, [rsi + 48]

    sqrtps  xmm0, xmm0
    sqrtps  xmm1, xmm1
    sqrtps  xmm2, xmm2
    sqrtps  xmm3, xmm3

    movups  [rdi], xmm0
    movups  [rdi + 16], xmm1
    movups  [rdi + 32], xmm2
    movups  [rdi + 48], xmm3

    add     rsi, 64
    add     rdi, 64
    dec     rcx
    jnz     .loop_unrolled

    and     rdx, 15
    jz      .done

.single_floats:
    cmp     rdx, 4
    jb      .residuals

    mov     rcx, rdx
    shr     rcx, 2

.loop_vector:
    movups  xmm0, [rsi]
    sqrtps  xmm0, xmm0
    movups  [rdi], xmm0
    add     rsi, 16
    add     rdi, 16
    dec     rcx
    jnz     .loop_vector

    and     rdx, 3
    jz      .done

.residuals:
    movss   xmm0, [rsi]
    sqrtss  xmm0, xmm0
    movss   [rdi], xmm0
    add     rsi, 4
    add     rdi, 4
    dec     rdx
    jnz     .residuals

.done:
    ret

; -----------------------------------------------------------------------------
; umath_sqrt_f32_array_approx - fast approximate sqrt of an array of floats
; args:    rdi = destination pointer (dst)
;          rsi = source pointer (src), all elements must be > 0
;          rdx = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_sqrt_f32_array_approx
umath_sqrt_f32_array_approx:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done
    test    rdx, rdx
    jz      .done

    cmp     rdx, 16
    jb      .single_floats

    mov     rcx, rdx
    shr     rcx, 4

.loop_unrolled:
    movups  xmm0, [rsi]
    movups  xmm1, [rsi + 16]
    movups  xmm2, [rsi + 32]
    movups  xmm3, [rsi + 48]

    rsqrtps xmm4, xmm0
    rsqrtps xmm5, xmm1
    rsqrtps xmm6, xmm2
    rsqrtps xmm7, xmm3

    mulps   xmm4, xmm0
    mulps   xmm5, xmm1
    mulps   xmm6, xmm2
    mulps   xmm7, xmm3

    movups  [rdi], xmm4
    movups  [rdi + 16], xmm5
    movups  [rdi + 32], xmm6
    movups  [rdi + 48], xmm7

    add     rsi, 64
    add     rdi, 64
    dec     rcx
    jnz     .loop_unrolled

    and     rdx, 15
    jz      .done

.single_floats:
    cmp     rdx, 4
    jb      .residuals

    mov     rcx, rdx
    shr     rcx, 2

.loop_vector:
    movups  xmm0, [rsi]
    rsqrtps xmm1, xmm0
    mulps   xmm0, xmm1
    movups  [rdi], xmm0
    add     rsi, 16
    add     rdi, 16
    dec     rcx
    jnz     .loop_vector

    and     rdx, 3
    jz      .done

.residuals:
    movss   xmm0, [rsi]
    rsqrtss xmm1, xmm0
    mulss   xmm0, xmm1
    movss   [rdi], xmm0
    add     rsi, 4
    add     rdi, 4
    dec     rdx
    jnz     .residuals

.done:
    ret

; -----------------------------------------------------------------------------
; umath_sqrt_f32_inplace - exact in-place sqrt of a float array
; args:    rdi = buffer pointer (buf)
;          rsi = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_sqrt_f32_inplace
umath_sqrt_f32_inplace:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done

    cmp     rsi, 16
    jb      .single_floats

    mov     rcx, rsi
    shr     rcx, 4

.loop_unrolled:
    movups  xmm0, [rdi]
    movups  xmm1, [rdi + 16]
    movups  xmm2, [rdi + 32]
    movups  xmm3, [rdi + 48]

    sqrtps  xmm0, xmm0
    sqrtps  xmm1, xmm1
    sqrtps  xmm2, xmm2
    sqrtps  xmm3, xmm3

    movups  [rdi], xmm0
    movups  [rdi + 16], xmm1
    movups  [rdi + 32], xmm2
    movups  [rdi + 48], xmm3

    add     rdi, 64
    dec     rcx
    jnz     .loop_unrolled

    and     rsi, 15
    jz      .done

.single_floats:
    cmp     rsi, 4
    jb      .residuals

    mov     rcx, rsi
    shr     rcx, 2

.loop_vector:
    movups  xmm0, [rdi]
    sqrtps  xmm0, xmm0
    movups  [rdi], xmm0
    add     rdi, 16
    dec     rcx
    jnz     .loop_vector

    and     rsi, 3
    jz      .done

.residuals:
    movss   xmm0, [rdi]
    sqrtss  xmm0, xmm0
    movss   [rdi], xmm0
    add     rdi, 4
    dec     rsi
    jnz     .residuals

.done:
    ret

%endif ; GUARD_LIB_UMATH_MATH_FN_SQRT_F32_ASM
