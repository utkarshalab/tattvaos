%ifndef GUARD_LIB_UMATH_SCALAR_SIGN_F32_ASM
%define GUARD_LIB_UMATH_SCALAR_SIGN_F32_ASM
; =============================================================================
; umath - unified math library
; scalar/sign_f32.asm - single-precision float sign (signum) implementations
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; Performance Optimizations:
;   - Vectorized element-wise sign mapping unrolled 4x (using SSE cmpltps with swapped operands).
;   - IEEE-754 compliant NaN propagation and signed zeros handling.
;   - In-place and copying sign mappings.
;   - Fast scalar helpers for positive and negative checks.
; =============================================================================

bits 64

section .rodata
align 16
signf32_one:      dd 1.0, 1.0, 1.0, 1.0
signf32_neg_one:  dd -1.0, -1.0, -1.0, -1.0
signf32_zero:     dd 0.0, 0.0, 0.0, 0.0

section .text

; -----------------------------------------------------------------------------
; signf32_vec - packed signum of one xmm vector
; args:    %1 = result register, %2 = input values (preserved)
;          %3, %4 = scratch registers
; expects: xmm12 = 1.0 lanes, xmm13 = -1.0 lanes, xmm14 = 0.0 lanes
;
; Uses ordered less-than compares (false on NaN) with swapped operands, so
; lanes that are neither > 0 nor < 0 (+/-0.0 and NaN) pass the input through
; unchanged, matching the scalar path (signed zero and NaN payload kept).
; -----------------------------------------------------------------------------
%macro signf32_vec 4
    movaps  %1, xmm14
    cmpltps %1, %2              ; %1 = 0.0 < val
    movaps  %3, %2
    cmpltps %3, xmm14           ; %3 = val < 0.0
    movaps  %4, %1
    orps    %4, %3               ; %4 = lanes with a definite sign
    andps   %1, xmm12            ; 1.0 where positive
    andps   %3, xmm13            ; -1.0 where negative
    orps    %1, %3
    andnps  %4, %2               ; val where +/-0.0 or NaN
    orps    %1, %4
%endmacro

; -----------------------------------------------------------------------------
; umath_sign_f32 - calculate signum of a scalar float
; args:    xmm0 = input value (val)
; returns: xmm0 = 1.0f (val > 0), -1.0f (val < 0), 0.0f (val == 0), NaN if NaN
; -----------------------------------------------------------------------------
global umath_sign_f32
umath_sign_f32:
    ; NaN check
    ucomiss xmm0, xmm0
    jp      .done               ; if unordered (NaN), return val (xmm0 is already NaN)

    ; Compare vs 0.0
    xorps   xmm1, xmm1          ; xmm1 = 0.0f
    ucomiss xmm0, xmm1
    je      .done               ; if equal to 0.0 (or -0.0), return val (xmm0 has zero)
    jb      .negative

    ; Positive path
    movss   xmm0, [rel signf32_one]
    ret

.negative:
    movss   xmm0, [rel signf32_neg_one]
.done:
    ret

; -----------------------------------------------------------------------------
; umath_sign_f32_array - compute element-wise signum of a float array
; args:    rdi = destination pointer (dst)
;          rsi = source pointer (src)
;          rdx = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_sign_f32_array
umath_sign_f32_array:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done
    test    rdx, rdx
    jz      .done

    movups  xmm12, [rel signf32_one]
    movups  xmm13, [rel signf32_neg_one]
    xorps   xmm14, xmm14        ; zero vector

    cmp     rdx, 16
    jb      .single_floats

    mov     rcx, rdx
    shr     rcx, 4              ; count of 16-float blocks

.loop_unrolled:
    ; Load 16 elements
    movups  xmm0, [rsi]
    movups  xmm1, [rsi + 16]
    movups  xmm2, [rsi + 32]
    movups  xmm3, [rsi + 48]

    ; Signum of each vector (see the macro above for the lane rules)
    
    ; Vector 0
    signf32_vec xmm4, xmm0, xmm5, xmm8

    ; Vector 1
    signf32_vec xmm6, xmm1, xmm7, xmm10

    ; Vector 2
    signf32_vec xmm8, xmm2, xmm5, xmm10

    ; Vector 3
    signf32_vec xmm10, xmm3, xmm7, xmm5

    ; Store results
    movups  [rdi], xmm4
    movups  [rdi + 16], xmm6
    movups  [rdi + 32], xmm8
    movups  [rdi + 48], xmm10

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
    signf32_vec xmm4, xmm0, xmm5, xmm8

    movups  [rdi], xmm4
    add     rsi, 16
    add     rdi, 16
    dec     rcx
    jnz     .loop_vector

    and     rdx, 3
    jz      .done

.residuals:
    movss   xmm0, [rsi]
    ucomiss xmm0, xmm0
    jp      .store_residual     ; if NaN, store val directly
    ucomiss xmm0, xmm14
    je      .store_residual     ; if 0.0, store val directly
    jb      .neg_residual

    movss   xmm0, [rel signf32_one]
    jmp     .store_residual

.neg_residual:
    movss   xmm0, [rel signf32_neg_one]

.store_residual:
    movss   [rdi], xmm0
    add     rsi, 4
    add     rdi, 4
    dec     rdx
    jnz     .residuals

.done:
    ret

; -----------------------------------------------------------------------------
; umath_sign_f32_inplace - in-place signum computation of a float array
; args:    rdi = buffer pointer (buf)
;          rsi = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_sign_f32_inplace
umath_sign_f32_inplace:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done

    movups  xmm12, [rel signf32_one]
    movups  xmm13, [rel signf32_neg_one]
    xorps   xmm14, xmm14

    cmp     rsi, 16
    jb      .single_floats

    mov     rcx, rsi
    shr     rcx, 4

.loop_unrolled:
    movups  xmm0, [rdi]
    movups  xmm1, [rdi + 16]
    movups  xmm2, [rdi + 32]
    movups  xmm3, [rdi + 48]

    ; Vector 0
    signf32_vec xmm4, xmm0, xmm5, xmm8

    ; Vector 1
    signf32_vec xmm6, xmm1, xmm7, xmm10

    ; Vector 2
    signf32_vec xmm8, xmm2, xmm5, xmm10

    ; Vector 3
    signf32_vec xmm10, xmm3, xmm7, xmm5

    ; Store results
    movups  [rdi], xmm4
    movups  [rdi + 16], xmm6
    movups  [rdi + 32], xmm8
    movups  [rdi + 48], xmm10

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
    signf32_vec xmm4, xmm0, xmm5, xmm8

    movups  [rdi], xmm4
    add     rdi, 16
    dec     rcx
    jnz     .loop_vector

    and     rsi, 3
    jz      .done

.residuals:
    movss   xmm0, [rdi]
    ucomiss xmm0, xmm0
    jp      .store_residual
    ucomiss xmm0, xmm14
    je      .store_residual
    jb      .neg_residual

    movss   xmm0, [rel signf32_one]
    jmp     .store_residual

.neg_residual:
    movss   xmm0, [rel signf32_neg_one]

.store_residual:
    movss   [rdi], xmm0
    add     rdi, 4
    dec     rsi
    jnz     .residuals

.done:
    ret

; -----------------------------------------------------------------------------
; umath_sign_f32_is_positive - check if float is strictly positive (> 0.0f)
; args:    xmm0 = input value (val)
; returns: eax = 1 if strictly positive, 0 otherwise
; -----------------------------------------------------------------------------
global umath_sign_f32_is_positive
umath_sign_f32_is_positive:
    xorps   xmm1, xmm1
    ucomiss xmm0, xmm1
    seta    al                  ; set if val > 0.0 (excludes NaN and equal)
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_sign_f32_is_negative - check if float is strictly negative (< 0.0f)
; args:    xmm0 = input value (val)
; returns: eax = 1 if strictly negative, 0 otherwise
; -----------------------------------------------------------------------------
global umath_sign_f32_is_negative
umath_sign_f32_is_negative:
    xorps   xmm1, xmm1
    ucomiss xmm1, xmm0
    seta    al                  ; set if 0.0 > val (excludes NaN and equal)
    movzx   eax, al
    ret

%endif ; GUARD_LIB_UMATH_SCALAR_SIGN_F32_ASM
