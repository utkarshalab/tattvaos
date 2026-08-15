%ifndef GUARD_LIB_UMATH_SCALAR_SIGN_F64_ASM
%define GUARD_LIB_UMATH_SCALAR_SIGN_F64_ASM
; =============================================================================
; umath - unified math library
; scalar/sign_f64.asm - double-precision float sign (signum) implementations
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; Performance Optimizations:
;   - Vectorized element-wise sign mapping unrolled 4x (using SSE2 cmpgtpd/cmpunordpd).
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

    ; For each vector, compute:
    ; mask_pos = val > 0.0
    ; mask_neg = 0.0 > val
    ; mask_nan = val != val (unordered)
    
    ; Vector 0
    movups  xmm4, xmm0          ; copy val
    movups  xmm5, xmm14         ; copy zero
    cmpgtpd xmm4, xmm14         ; xmm4 = val > 0.0
    cmpgtpd xmm5, xmm0          ; xmm5 = 0.0 > val
    movups  xmm8, xmm0
    cmpunordpd xmm8, xmm8       ; xmm8 = NaN mask
    pand    xmm4, xmm12         ; 1.0 & mask_pos
    pand    xmm5, xmm13         ; -1.0 & mask_neg
    por     xmm4, xmm5          ; combined signs (zeros are 0.0)
    pand    xmm8, xmm0          ; inputs where NaN
    movups  xmm9, xmm0
    cmpordpd xmm9, xmm0         ; not NaN mask
    pand    xmm4, xmm9          ; clear slots where NaN
    por     xmm4, xmm8          ; insert original NaNs

    ; Vector 1
    movups  xmm6, xmm1
    movups  xmm7, xmm14
    cmpgtpd xmm6, xmm14
    cmpgtpd xmm7, xmm1
    movups  xmm10, xmm1
    cmpunordpd xmm10, xmm10
    pand    xmm6, xmm12
    pand    xmm7, xmm13
    por     xmm6, xmm7
    pand    xmm10, xmm1
    movups  xmm9, xmm1
    cmpordpd xmm9, xmm1
    pand    xmm6, xmm9
    por     xmm6, xmm10

    ; Vector 2
    movups  xmm8, xmm2
    movups  xmm5, xmm14
    cmpgtpd xmm8, xmm14
    cmpgtpd xmm5, xmm2
    movups  xmm10, xmm2
    cmpunordpd xmm10, xmm10
    pand    xmm8, xmm12
    pand    xmm5, xmm13
    por     xmm8, xmm5
    pand    xmm10, xmm2
    movups  xmm9, xmm2
    cmpordpd xmm9, xmm2
    pand    xmm8, xmm9
    por     xmm8, xmm10

    ; Vector 3
    movups  xmm10, xmm3
    movups  xmm7, xmm14
    cmpgtpd xmm10, xmm14
    cmpgtpd xmm7, xmm3
    movups  xmm5, xmm3
    cmpunordpd xmm5, xmm5
    pand    xmm10, xmm12
    pand    xmm7, xmm13
    por     xmm10, xmm7
    pand    xmm5, xmm3
    movups  xmm9, xmm3
    cmpordpd xmm9, xmm3
    pand    xmm10, xmm9
    por     xmm10, xmm5

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
    movups  xmm4, xmm0
    movups  xmm5, xmm14
    cmpgtpd xmm4, xmm14
    cmpgtpd xmm5, xmm0
    movups  xmm8, xmm0
    cmpunordpd xmm8, xmm8
    pand    xmm4, xmm12
    pand    xmm5, xmm13
    por     xmm4, xmm5
    pand    xmm8, xmm0
    movups  xmm9, xmm0
    cmpordpd xmm9, xmm0
    pand    xmm4, xmm9
    por     xmm4, xmm8

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
    movups  xmm4, xmm0
    movups  xmm5, xmm14
    cmpgtpd xmm4, xmm14
    cmpgtpd xmm5, xmm0
    movups  xmm8, xmm0
    cmpunordpd xmm8, xmm8
    pand    xmm4, xmm12
    pand    xmm5, xmm13
    por     xmm4, xmm5
    pand    xmm8, xmm0
    movups  xmm9, xmm0
    cmpordpd xmm9, xmm0
    pand    xmm4, xmm9
    por     xmm4, xmm8

    ; Vector 1
    movups  xmm6, xmm1
    movups  xmm7, xmm14
    cmpgtpd xmm6, xmm14
    cmpgtpd xmm7, xmm1
    movups  xmm10, xmm1
    cmpunordpd xmm10, xmm10
    pand    xmm6, xmm12
    pand    xmm7, xmm13
    por     xmm6, xmm7
    pand    xmm10, xmm1
    movups  xmm9, xmm1
    cmpordpd xmm9, xmm1
    pand    xmm6, xmm9
    por     xmm6, xmm10

    ; Vector 2
    movups  xmm8, xmm2
    movups  xmm5, xmm14
    cmpgtpd xmm8, xmm14
    cmpgtpd xmm5, xmm2
    movups  xmm10, xmm2
    cmpunordpd xmm10, xmm10
    pand    xmm8, xmm12
    pand    xmm5, xmm13
    por     xmm8, xmm5
    pand    xmm10, xmm2
    movups  xmm9, xmm2
    cmpordpd xmm9, xmm2
    pand    xmm8, xmm9
    por     xmm8, xmm10

    ; Vector 3
    movups  xmm10, xmm3
    movups  xmm7, xmm14
    cmpgtpd xmm10, xmm14
    cmpgtpd xmm7, xmm3
    movups  xmm5, xmm3
    cmpunordpd xmm5, xmm5
    pand    xmm10, xmm12
    pand    xmm7, xmm13
    por     xmm10, xmm7
    pand    xmm5, xmm3
    movups  xmm9, xmm3
    cmpordpd xmm9, xmm3
    pand    xmm10, xmm9
    por     xmm10, xmm5

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
    movups  xmm4, xmm0
    movups  xmm5, xmm14
    cmpgtpd xmm4, xmm14
    cmpgtpd xmm5, xmm0
    movups  xmm8, xmm0
    cmpunordpd xmm8, xmm8
    pand    xmm4, xmm12
    pand    xmm5, xmm13
    por     xmm4, xmm5
    pand    xmm8, xmm0
    movups  xmm9, xmm0
    cmpordpd xmm9, xmm0
    pand    xmm4, xmm9
    por     xmm4, xmm8

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
