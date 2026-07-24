; =============================================================================
; umath - unified math library
; scalar/neg_f64.asm - double-precision float negation implementations
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; Performance Optimizations:
;   - Vectorized element-wise negation unrolled 4x (using SSE2 xorpd).
;   - Vectorized negative absolute value unrolled 4x (using SSE2 orpd).
;   - In-place and copying negation mappings.
;   - Completely branchless implementation.
; =============================================================================

bits 64

section .rodata
align 16
mask_sign_f64:      dq 0x8000000000000000, 0x8000000000000000

section .text

; -----------------------------------------------------------------------------
; umath_neg_f64 - negate a scalar double (branchless)
; args:    xmm0 = input value (val)
; returns: xmm0 = negated value (-val)
; -----------------------------------------------------------------------------
global umath_neg_f64
umath_neg_f64:
    movsd   xmm1, [rel mask_sign_f64]
    xorpd   xmm0, xmm1          ; toggle sign bit
    ret

; -----------------------------------------------------------------------------
; umath_neg_f64_abs_neg - compute negative absolute value of scalar double (-abs(val))
; args:    xmm0 = input value (val)
; returns: xmm0 = negative absolute value
; -----------------------------------------------------------------------------
global umath_neg_f64_abs_neg
umath_neg_f64_abs_neg:
    movsd   xmm1, [rel mask_sign_f64]
    orpd    xmm0, xmm1          ; force sign bit to 1 (negative)
    ret

; -----------------------------------------------------------------------------
; umath_neg_f64_array - negate an array of doubles
; args:    rdi = destination pointer (dst)
;          rsi = source pointer (src)
;          rdx = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_neg_f64_array
umath_neg_f64_array:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done
    test    rdx, rdx
    jz      .done

    movups  xmm15, [rel mask_sign_f64]

    cmp     rdx, 8
    jb      .single_doubles

    mov     rcx, rdx
    shr     rcx, 3              ; count of 8-double blocks (each holds 2 doubles)

.loop_unrolled:
    ; Load 8 doubles
    movups  xmm0, [rsi]
    movups  xmm1, [rsi + 16]
    movups  xmm2, [rsi + 32]
    movups  xmm3, [rsi + 48]

    ; Negate by XORing sign bit
    xorpd   xmm0, xmm15
    xorpd   xmm1, xmm15
    xorpd   xmm2, xmm15
    xorpd   xmm3, xmm15

    ; Store results
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
    xorpd   xmm0, xmm15
    movups  [rdi], xmm0
    add     rsi, 16
    add     rdi, 16
    dec     rcx
    jnz     .loop_vector

    and     rdx, 1
    jz      .done

.residuals:
    movsd   xmm0, [rsi]
    xorpd   xmm0, xmm15
    movsd   [rdi], xmm0
    add     rsi, 8
    add     rdi, 8
    dec     rdx
    jnz     .residuals

.done:
    ret

; -----------------------------------------------------------------------------
; umath_neg_f64_inplace - in-place negation of double array
; args:    rdi = buffer pointer (buf)
;          rsi = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_neg_f64_inplace
umath_neg_f64_inplace:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done

    movups  xmm15, [rel mask_sign_f64]

    cmp     rsi, 8
    jb      .single_doubles

    mov     rcx, rsi
    shr     rcx, 3

.loop_unrolled:
    movups  xmm0, [rdi]
    movups  xmm1, [rdi + 16]
    movups  xmm2, [rdi + 32]
    movups  xmm3, [rdi + 48]

    xorpd   xmm0, xmm15
    xorpd   xmm1, xmm15
    xorpd   xmm2, xmm15
    xorpd   xmm3, xmm15

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
    xorpd   xmm0, xmm15
    movups  [rdi], xmm0
    add     rdi, 16
    dec     rcx
    jnz     .loop_vector

    and     rsi, 1
    jz      .done

.residuals:
    movsd   xmm0, [rdi]
    xorpd   xmm0, xmm15
    movsd   [rdi], xmm0
    add     rdi, 8
    dec     rsi
    jnz     .residuals

.done:
    ret

; -----------------------------------------------------------------------------
; umath_neg_f64_abs_neg_array - compute negative absolute value of a double array
; args:    rdi = destination pointer (dst)
;          rsi = source pointer (src)
;          rdx = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_neg_f64_abs_neg_array
umath_neg_f64_abs_neg_array:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done
    test    rdx, rdx
    jz      .done

    movups  xmm15, [rel mask_sign_f64]

    cmp     rdx, 8
    jb      .single_doubles

    mov     rcx, rdx
    shr     rcx, 3

.loop_unrolled:
    movups  xmm0, [rsi]
    movups  xmm1, [rsi + 16]
    movups  xmm2, [rsi + 32]
    movups  xmm3, [rsi + 48]

    ; Force sign bit to 1 (negative) using OR
    orpd    xmm0, xmm15
    orpd    xmm1, xmm15
    orpd    xmm2, xmm15
    orpd    xmm3, xmm15

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
    orpd    xmm0, xmm15
    movups  [rdi], xmm0
    add     rsi, 16
    add     rdi, 16
    dec     rcx
    jnz     .loop_vector

    and     rdx, 1
    jz      .done

.residuals:
    movsd   xmm0, [rsi]
    orpd    xmm0, xmm15
    movsd   [rdi], xmm0
    add     rsi, 8
    add     rdi, 8
    dec     rdx
    jnz     .residuals

.done:
    ret

; -----------------------------------------------------------------------------
; umath_neg_f64_abs_neg_inplace - in-place negative absolute value of a double array
; args:    rdi = buffer pointer (buf)
;          rsi = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_neg_f64_abs_neg_inplace
umath_neg_f64_abs_neg_inplace:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done

    movups  xmm15, [rel mask_sign_f64]

    cmp     rsi, 8
    jb      .single_doubles

    mov     rcx, rsi
    shr     rcx, 3

.loop_unrolled:
    movups  xmm0, [rdi]
    movups  xmm1, [rdi + 16]
    movups  xmm2, [rdi + 32]
    movups  xmm3, [rdi + 48]

    orpd    xmm0, xmm15
    orpd    xmm1, xmm15
    orpd    xmm2, xmm15
    orpd    xmm3, xmm15

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
    orpd    xmm0, xmm15
    movups  [rdi], xmm0
    add     rdi, 16
    dec     rcx
    jnz     .loop_vector

    and     rsi, 1
    jz      .done

.residuals:
    movsd   xmm0, [rdi]
    orpd    xmm0, xmm15
    movsd   [rdi], xmm0
    add     rdi, 8
    dec     rsi
    jnz     .residuals

.done:
    ret
