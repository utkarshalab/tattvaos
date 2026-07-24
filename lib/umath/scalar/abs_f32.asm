; =============================================================================
; umath - unified math library
; scalar/abs_f32.asm - single-precision float absolute value implementations
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; IEEE 754 Single-Precision Float Structure:
;
;   31 30         23 22                               0
;   +-+-------------+---------------------------------+
;   |s|  exponent   |            mantissa             |
;   +-+-------------+---------------------------------+
;
;   - s: Sign bit (bit 31). Cleared to 0 for absolute value.
;   - Exponent: Bits 30-23 (8 bits).
;   - Mantissa: Bits 22-0 (23 bits).
;
; Design & Optimization:
;   - Fast bitwise AND masking to clear sign bit.
;   - Unrolled loops (4x stride) in array mappings for maximum bandwidth.
;   - Zero-overhead branchless NaN/Inf checkers.
;   - Sign bit check and counting utilities.
; =============================================================================

bits 64
section .text

; 128-bit absolute value mask (clears bit 31 of each 32-bit slot)
align 16
mask_abs_f32:
    dd 0x7FFFFFFF, 0x7FFFFFFF, 0x7FFFFFFF, 0x7FFFFFFF

; 128-bit sign bit mask (isolates bit 31 of each 32-bit slot)
align 16
mask_sign_f32:
    dd 0x80000000, 0x80000000, 0x80000000, 0x80000000

; -----------------------------------------------------------------------------
; umath_abs_f32 - scalar single-precision absolute value
; args:    xmm0 = input float (val)
; returns: xmm0 = absolute value of input float
; -----------------------------------------------------------------------------
global umath_abs_f32
umath_abs_f32:
    movaps  xmm1, [mask_abs_f32]
    andps   xmm0, xmm1
    ret

; -----------------------------------------------------------------------------
; umath_abs_f32_array - compute absolute value for an array of floats
; args:    rdi = destination pointer (dst)
;          rsi = source pointer (src)
;          rdx = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_abs_f32_array
umath_abs_f32_array:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done
    test    rdx, rdx
    jz      .done

    movaps  xmm15, [mask_abs_f32]

    cmp     rdx, 16
    jb      .single_floats

    mov     rcx, rdx
    shr     rcx, 4              ; rcx = number of 16-float (64-byte) blocks

.loop_unrolled:
    movups  xmm0, [rsi]
    movups  xmm1, [rsi + 16]
    movups  xmm2, [rsi + 32]
    movups  xmm3, [rsi + 48]

    andps   xmm0, xmm15
    andps   xmm1, xmm15
    andps   xmm2, xmm15
    andps   xmm3, xmm15

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
    andps   xmm0, xmm15
    movups  [rdi], xmm0
    add     rsi, 16
    add     rdi, 16
    dec     rcx
    jnz     .loop_vector

    and     rdx, 3
    jz      .done

.residuals:
    movss   xmm0, [rsi]
    andss   xmm0, xmm15
    movss   [rdi], xmm0
    add     rsi, 4
    add     rdi, 4
    dec     rdx
    jnz     .residuals

.done:
    ret

; -----------------------------------------------------------------------------
; umath_abs_f32_inplace - compute in-place absolute value for an array of floats
; args:    rdi = buffer pointer (buf)
;          rsi = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_abs_f32_inplace
umath_abs_f32_inplace:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done

    movaps  xmm15, [mask_abs_f32]

    cmp     rsi, 16
    jb      .single_floats

    mov     rcx, rsi
    shr     rcx, 4

.loop_unrolled:
    movups  xmm0, [rdi]
    movups  xmm1, [rdi + 16]
    movups  xmm2, [rdi + 32]
    movups  xmm3, [rdi + 48]

    andps   xmm0, xmm15
    andps   xmm1, xmm15
    andps   xmm2, xmm15
    andps   xmm3, xmm15

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
    andps   xmm0, xmm15
    movups  [rdi], xmm0
    add     rdi, 16
    dec     rcx
    jnz     .loop_vector

    and     rsi, 3
    jz      .done

.residuals:
    movss   xmm0, [rdi]
    andss   xmm0, xmm15
    movss   [rdi], xmm0
    add     rdi, 4
    dec     rsi
    jnz     .residuals

.done:
    ret

; -----------------------------------------------------------------------------
; umath_abs_f32_isnan - check if single-precision float is NaN
; args:    xmm0 = input float (val)
; returns: eax = 1 (is NaN) or 0 (is not NaN)
; -----------------------------------------------------------------------------
global umath_abs_f32_isnan
umath_abs_f32_isnan:
    ucomiss xmm0, xmm0
    setp    al
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_abs_f32_isinf - check if single-precision float is Infinity (+/- Inf)
; args:    xmm0 = input float (val)
; returns: eax = 1 (is Inf) or 0 (is not Inf)
; -----------------------------------------------------------------------------
global umath_abs_f32_isinf
umath_abs_f32_isinf:
    movd    ecx, xmm0
    and     ecx, 0x7FFFFFFF
    cmp     ecx, 0x7F800000
    sete    al
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_abs_f32_copysign - return absolute value of val with sign of sign_val
; args:    xmm0 = magnitude value (val)
;          xmm1 = sign value (sign_val)
; returns: xmm0 = absolute value of val with sign of sign_val
; -----------------------------------------------------------------------------
global umath_abs_f32_copysign
umath_abs_f32_copysign:
    movss   xmm2, [mask_abs_f32]
    andps   xmm0, xmm2
    andnps  xmm2, xmm1
    orps    xmm0, xmm2
    ret

; -----------------------------------------------------------------------------
; umath_abs_f32_count_negative - count how many elements in float array are negative
; args:    rdi = source pointer (src)
;          rsi = size of array (count)
; returns: rax = count of negative elements
; -----------------------------------------------------------------------------
global umath_abs_f32_count_negative
umath_abs_f32_count_negative:
    xor     rax, rax            ; count = 0
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done

    movaps  xmm15, [mask_sign_f32]

    cmp     rsi, 16
    jb      .single_floats

    mov     rcx, rsi
    shr     rcx, 4

.loop_unrolled:
    movups  xmm0, [rdi]
    movups  xmm1, [rdi + 16]
    movups  xmm2, [rdi + 32]
    movups  xmm3, [rdi + 48]

    ; Check if negative: bitwise AND with sign mask
    andps   xmm0, xmm15
    andps   xmm1, xmm15
    andps   xmm2, xmm15
    andps   xmm3, xmm15

    ; movmskps extracts sign bit of each float to a 4-bit integer
    movmskps edx, xmm0
    popcnt  edx, edx
    add     rax, rdx

    movmskps edx, xmm1
    popcnt  edx, edx
    add     rax, rdx

    movmskps edx, xmm2
    popcnt  edx, edx
    add     rax, rdx

    movmskps edx, xmm3
    popcnt  edx, edx
    add     rax, rdx

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
    andps   xmm0, xmm15
    movmskps edx, xmm0
    popcnt  edx, edx
    add     rax, rdx
    add     rdi, 16
    dec     rcx
    jnz     .loop_vector

    and     rsi, 3
    jz      .done

.residuals:
    movss   xmm0, [rdi]
    movd    ecx, xmm0
    test    ecx, ecx
    jns     .next_residual       ; sign bit not set, not negative
    inc     rax

.next_residual:
    add     rdi, 4
    dec     rsi
    jnz     .residuals

.done:
    ret

; -----------------------------------------------------------------------------
; umath_abs_f32_is_all_positive - checks if all elements are non-negative
; args:    rdi = source pointer (src)
;          rsi = size of array (count)
; returns: eax = 1 if all elements are positive or zero, 0 otherwise
; -----------------------------------------------------------------------------
global umath_abs_f32_is_all_positive
umath_abs_f32_is_all_positive:
    mov     eax, 1              ; default to true
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done

    movaps  xmm15, [mask_sign_f32]

    cmp     rsi, 16
    jb      .single_floats

    mov     rcx, rsi
    shr     rcx, 4

.loop_unrolled:
    movups  xmm0, [rdi]
    movups  xmm1, [rdi + 16]
    movups  xmm2, [rdi + 32]
    movups  xmm3, [rdi + 48]

    orps    xmm0, xmm1
    orps    xmm2, xmm3
    orps    xmm0, xmm2
    andps   xmm0, xmm15

    movmskps edx, xmm0
    test    edx, edx
    jnz     .not_all_positive

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
    andps   xmm0, xmm15
    movmskps edx, xmm0
    test    edx, edx
    jnz     .not_all_positive
    add     rdi, 16
    dec     rcx
    jnz     .loop_vector

    and     rsi, 3
    jz      .done

.residuals:
    movss   xmm0, [rdi]
    movd    ecx, xmm0
    test    ecx, ecx
    js      .not_all_positive
    add     rdi, 4
    dec     rsi
    jnz     .residuals
    ret

.not_all_positive:
    xor     eax, eax
.done:
    ret
