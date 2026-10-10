%ifndef GUARD_LIB_UMATH_SCALAR_SIGN_F64_ASM
%define GUARD_LIB_UMATH_SCALAR_SIGN_F64_ASM
; =============================================================================
; umath - unified math library
; scalar/sign_f64.asm - double-precision float sign (signum) implementations
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; Performance Optimizations:
;   - Vectorized element-wise sign mapping unrolled 4x (using SSE2 cmpltpd with swapped operands).
;   - IEEE-754 compliant NaN propagation and signed zeros handling.
;   - In-place and copying sign mappings.
;   - Fast scalar helpers for positive and negative checks.
; =============================================================================

bits 64

section .rodata
align 16
signf64_one:      dq 1.0, 1.0
signf64_neg_one:  dq -1.0, -1.0
signf64_zero:     dq 0.0, 0.0

section .text

; -----------------------------------------------------------------------------
; signf64_vec - packed signum of one xmm vector
; args:    %1 = result register, %2 = input values (preserved)
;          %3, %4 = scratch registers
; expects: xmm12 = 1.0 lanes, xmm13 = -1.0 lanes, xmm14 = 0.0 lanes
;
; Uses ordered less-than compares (false on NaN) with swapped operands, so
; lanes that are neither > 0 nor < 0 (+/-0.0 and NaN) pass the input through
; unchanged, matching the scalar path (signed zero and NaN payload kept).
; -----------------------------------------------------------------------------
%macro signf64_vec 4
    movapd  %1, xmm14
    cmpltpd %1, %2              ; %1 = 0.0 < val
    movapd  %3, %2
    cmpltpd %3, xmm14           ; %3 = val < 0.0
    movapd  %4, %1
    orpd    %4, %3               ; %4 = lanes with a definite sign
    andpd   %1, xmm12            ; 1.0 where positive
    andpd   %3, xmm13            ; -1.0 where negative
    orpd    %1, %3
    andnpd  %4, %2               ; val where +/-0.0 or NaN
    orpd    %1, %4
%endmacro

; -----------------------------------------------------------------------------
; umath_sign_f64 - calculate signum of a scalar double
; args:    xmm0 = input value (val)
; returns: xmm0 = 1.0 (val > 0), -1.0 (val < 0), 0.0 (val == 0), NaN if NaN
; -----------------------------------------------------------------------------
global umath_sign_f64
umath_sign_f64:
    ; NaN check
    ucomisd xmm0, xmm0
    jp      .done               ; if unordered (NaN), return val (xmm0 is already NaN)

    ; Compare vs 0.0
    xorpd   xmm1, xmm1          ; xmm1 = 0.0
    ucomisd xmm0, xmm1
    je      .done               ; if equal to 0.0 (or -0.0), return val (xmm0 has zero)
    jb      .negative

    ; Positive path
    movsd   xmm0, [rel signf64_one]
    ret

.negative:
    movsd   xmm0, [rel signf64_neg_one]
.done:
    ret

; -----------------------------------------------------------------------------
; umath_sign_f64_array - compute element-wise signum of a double array
; args:    rdi = destination pointer (dst)
;          rsi = source pointer (src)
;          rdx = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_sign_f64_array
umath_sign_f64_array:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done
    test    rdx, rdx
    jz      .done

    movups  xmm12, [rel signf64_one]
    movups  xmm13, [rel signf64_neg_one]
    xorpd   xmm14, xmm14        ; zero vector

    cmp     rdx, 8
    jb      .single_doubles

    mov     rcx, rdx
    shr     rcx, 3              ; count of 8-double blocks (each holds 2 doubles, 64 bytes)

.loop_unrolled:
    ; Load 8 elements (4 xmm registers)
    movups  xmm0, [rsi]
    movups  xmm1, [rsi + 16]
    movups  xmm2, [rsi + 32]
    movups  xmm3, [rsi + 48]

    ; Signum of each vector (see the macro above for the lane rules)
    
    ; Vector 0
    signf64_vec xmm4, xmm0, xmm5, xmm8

    ; Vector 1
    signf64_vec xmm6, xmm1, xmm7, xmm10

    ; Vector 2
    signf64_vec xmm8, xmm2, xmm5, xmm10

    ; Vector 3
    signf64_vec xmm10, xmm3, xmm7, xmm5

    ; Store results
    movups  [rdi], xmm4
    movups  [rdi + 16], xmm6
    movups  [rdi + 32], xmm8
    movups  [rdi + 48], xmm10

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
    signf64_vec xmm4, xmm0, xmm5, xmm8

    movups  [rdi], xmm4
    add     rsi, 16
    add     rdi, 16
    dec     rcx
    jnz     .loop_vector

    and     rdx, 1
    jz      .done

.residuals:
    movsd   xmm0, [rsi]
    ucomisd xmm0, xmm0
    jp      .store_residual     ; if NaN, store val directly
    ucomisd xmm0, xmm14
    je      .store_residual     ; if 0.0, store val directly
    jb      .neg_residual

    movsd   xmm0, [rel signf64_one]
    jmp     .store_residual

.neg_residual:
    movsd   xmm0, [rel signf64_neg_one]

.store_residual:
    movsd   [rdi], xmm0
    add     rsi, 8
    add     rdi, 8
    dec     rdx
    jnz     .residuals

.done:
    ret

; -----------------------------------------------------------------------------
; umath_sign_f64_inplace - in-place signum computation of a double array
; args:    rdi = buffer pointer (buf)
;          rsi = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_sign_f64_inplace
umath_sign_f64_inplace:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done

    movups  xmm12, [rel signf64_one]
    movups  xmm13, [rel signf64_neg_one]
    xorpd   xmm14, xmm14

    cmp     rsi, 8
    jb      .single_doubles

    mov     rcx, rsi
    shr     rcx, 3

.loop_unrolled:
    movups  xmm0, [rdi]
    movups  xmm1, [rdi + 16]
    movups  xmm2, [rdi + 32]
    movups  xmm3, [rdi + 48]

    ; Vector 0
    signf64_vec xmm4, xmm0, xmm5, xmm8

    ; Vector 1
    signf64_vec xmm6, xmm1, xmm7, xmm10

    ; Vector 2
    signf64_vec xmm8, xmm2, xmm5, xmm10

    ; Vector 3
    signf64_vec xmm10, xmm3, xmm7, xmm5

    ; Store results
    movups  [rdi], xmm4
    movups  [rdi + 16], xmm6
    movups  [rdi + 32], xmm8
    movups  [rdi + 48], xmm10

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
    signf64_vec xmm4, xmm0, xmm5, xmm8

    movups  [rdi], xmm4
    add     rdi, 16
    dec     rcx
    jnz     .loop_vector

    and     rsi, 1
    jz      .done

.residuals:
    movsd   xmm0, [rdi]
    ucomisd xmm0, xmm0
    jp      .store_residual
    ucomisd xmm0, xmm14
    je      .store_residual
    jb      .neg_residual

    movsd   xmm0, [rel signf64_one]
    jmp     .store_residual

.neg_residual:
    movsd   xmm0, [rel signf64_neg_one]

.store_residual:
    movsd   [rdi], xmm0
    add     rdi, 8
    dec     rsi
    jnz     .residuals

.done:
    ret

; -----------------------------------------------------------------------------
; umath_sign_f64_is_positive - check if double is strictly positive (> 0.0)
; args:    xmm0 = input value (val)
; returns: eax = 1 if strictly positive, 0 otherwise
; -----------------------------------------------------------------------------
global umath_sign_f64_is_positive
umath_sign_f64_is_positive:
    xorpd   xmm1, xmm1
    ucomisd xmm0, xmm1
    seta    al                  ; set if val > 0.0 (excludes NaN and equal)
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_sign_f64_is_negative - check if double is strictly negative (< 0.0)
; args:    xmm0 = input value (val)
; returns: eax = 1 if strictly negative, 0 otherwise
; -----------------------------------------------------------------------------
global umath_sign_f64_is_negative
umath_sign_f64_is_negative:
    xorpd   xmm1, xmm1
    ucomisd xmm1, xmm0
    seta    al                  ; set if 0.0 > val (excludes NaN and equal)
    movzx   eax, al
    ret

%endif ; GUARD_LIB_UMATH_SCALAR_SIGN_F64_ASM
