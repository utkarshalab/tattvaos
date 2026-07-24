; =============================================================================
; umath - unified math library
; scalar/neg_f32.asm - single-precision float negation implementations
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; Performance Optimizations:
;   - Vectorized element-wise negation unrolled 4x (using SSE xorps).
;   - Vectorized negative absolute value unrolled 4x (using SSE orps).
;   - In-place and copying negation mappings.
;   - Completely branchless implementation.
; =============================================================================

bits 64

section .rodata
align 16
mask_sign_f32:      dd 0x80000000, 0x80000000, 0x80000000, 0x80000000

section .text

; -----------------------------------------------------------------------------
; umath_neg_f32 - negate a scalar float (branchless)
; args:    xmm0 = input value (val)
; returns: xmm0 = negated value (-val)
; -----------------------------------------------------------------------------
global umath_neg_f32
umath_neg_f32:
    movss   xmm1, [rel mask_sign_f32]
    xorps   xmm0, xmm1          ; toggle sign bit
    ret

; -----------------------------------------------------------------------------
; umath_neg_f32_abs_neg - compute negative absolute value of scalar float (-abs(val))
; args:    xmm0 = input value (val)
; returns: xmm0 = negative absolute value
; -----------------------------------------------------------------------------
global umath_neg_f32_abs_neg
umath_neg_f32_abs_neg:
    movss   xmm1, [rel mask_sign_f32]
    orps    xmm0, xmm1          ; force sign bit to 1 (negative)
    ret

; -----------------------------------------------------------------------------
; umath_neg_f32_array - negate an array of floats
; args:    rdi = destination pointer (dst)
;          rsi = source pointer (src)
;          rdx = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_neg_f32_array
umath_neg_f32_array:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done
    test    rdx, rdx
    jz      .done

    movups  xmm15, [rel mask_sign_f32]

    cmp     rdx, 16
    jb      .single_floats

    mov     rcx, rdx
    shr     rcx, 4              ; count of 16-float blocks

.loop_unrolled:
    ; Load 16 floats
    movups  xmm0, [rsi]
    movups  xmm1, [rsi + 16]
    movups  xmm2, [rsi + 32]
    movups  xmm3, [rsi + 48]

    ; Negate by XORing sign bit
    xorps   xmm0, xmm15
    xorps   xmm1, xmm15
    xorps   xmm2, xmm15
    xorps   xmm3, xmm15

    ; Store results
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
    xorps   xmm0, xmm15
    movups  [rdi], xmm0
    add     rsi, 16
    add     rdi, 16
    dec     rcx
    jnz     .loop_vector

    and     rdx, 3
    jz      .done

.residuals:
    movss   xmm0, [rsi]
    xorps   xmm0, xmm15
    movss   [rdi], xmm0
    add     rsi, 4
    add     rdi, 4
    dec     rdx
    jnz     .residuals

.done:
    ret

; -----------------------------------------------------------------------------
; umath_neg_f32_inplace - in-place negation of float array
; args:    rdi = buffer pointer (buf)
;          rsi = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_neg_f32_inplace
umath_neg_f32_inplace:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done

    movups  xmm15, [rel mask_sign_f32]

    cmp     rsi, 16
    jb      .single_floats

    mov     rcx, rsi
    shr     rcx, 4

.loop_unrolled:
    movups  xmm0, [rdi]
    movups  xmm1, [rdi + 16]
    movups  xmm2, [rdi + 32]
    movups  xmm3, [rdi + 48]

    xorps   xmm0, xmm15
    xorps   xmm1, xmm15
    xorps   xmm2, xmm15
    xorps   xmm3, xmm15

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
    xorps   xmm0, xmm15
    movups  [rdi], xmm0
    add     rdi, 16
    dec     rcx
    jnz     .loop_vector

    and     rsi, 3
    jz      .done

.residuals:
    movss   xmm0, [rdi]
    xorps   xmm0, xmm15
    movss   [rdi], xmm0
    add     rdi, 4
    dec     rsi
    jnz     .residuals

.done:
    ret

; -----------------------------------------------------------------------------
; umath_neg_f32_abs_neg_array - compute negative absolute value of a float array
; args:    rdi = destination pointer (dst)
;          rsi = source pointer (src)
;          rdx = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_neg_f32_abs_neg_array
umath_neg_f32_abs_neg_array:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done
    test    rdx, rdx
    jz      .done

    movups  xmm15, [rel mask_sign_f32]

    cmp     rdx, 16
    jb      .single_floats

    mov     rcx, rdx
    shr     rcx, 4

.loop_unrolled:
    movups  xmm0, [rsi]
    movups  xmm1, [rsi + 16]
    movups  xmm2, [rsi + 32]
    movups  xmm3, [rsi + 48]

    ; Force sign bit to 1 (negative) using OR
    orps    xmm0, xmm15
    orps    xmm1, xmm15
    orps    xmm2, xmm15
    orps    xmm3, xmm15

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
    orps    xmm0, xmm15
    movups  [rdi], xmm0
    add     rsi, 16
    add     rdi, 16
    dec     rcx
    jnz     .loop_vector

    and     rdx, 3
    jz      .done

.residuals:
    movss   xmm0, [rsi]
    orps    xmm0, xmm15
    movss   [rdi], xmm0
    add     rsi, 4
    add     rdi, 4
    dec     rdx
    jnz     .residuals

.done:
    ret

; -----------------------------------------------------------------------------
; umath_neg_f32_abs_neg_inplace - in-place negative absolute value of a float array
; args:    rdi = buffer pointer (buf)
;          rsi = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_neg_f32_abs_neg_inplace
umath_neg_f32_abs_neg_inplace:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done

    movups  xmm15, [rel mask_sign_f32]

    cmp     rsi, 16
    jb      .single_floats

    mov     rcx, rsi
    shr     rcx, 4

.loop_unrolled:
    movups  xmm0, [rdi]
    movups  xmm1, [rdi + 16]
    movups  xmm2, [rdi + 32]
    movups  xmm3, [rdi + 48]

    orps    xmm0, xmm15
    orps    xmm1, xmm15
    orps    xmm2, xmm15
    orps    xmm3, xmm15

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
    orps    xmm0, xmm15
    movups  [rdi], xmm0
    add     rdi, 16
    dec     rcx
    jnz     .loop_vector

    and     rsi, 3
    jz      .done

.residuals:
    movss   xmm0, [rdi]
    orps    xmm0, xmm15
    movss   [rdi], xmm0
    add     rdi, 4
    dec     rsi
    jnz     .residuals

.done:
    ret
