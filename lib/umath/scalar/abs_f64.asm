; =============================================================================
; umath - unified math library
; scalar/abs_f64.asm - double-precision float absolute value implementations
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; IEEE 754 Double-Precision Float Structure:
;
;   63 62         52 51                               0
;   +-+-------------+---------------------------------+
;   |s|  exponent   |            mantissa             |
;   +-+-------------+---------------------------------+
;
;   - s: Sign bit (bit 63). Cleared to 0 for absolute value.
;   - Exponent: Bits 62-52 (11 bits).
;   - Mantissa: Bits 51-0 (52 bits).
;
; Design & Optimization:
;   - Bitwise AND masking to clear sign bit on doubles.
;   - Unrolled loops (4x stride) in array mappings for maximum double bandwidth.
;   - Zero-overhead branchless NaN/Inf checkers.
;   - Sign bit check and counting utilities.
; =============================================================================

bits 64
section .text

; 128-bit absolute value mask (clears bit 63 of each 64-bit slot)
align 16
mask_abs_f64:
    dq 0x7FFFFFFFFFFFFFFF, 0x7FFFFFFFFFFFFFFF

; 128-bit sign bit mask (isolates bit 63 of each 64-bit slot)
align 16
mask_sign_f64:
    dq 0x8000000000000000, 0x8000000000000000

; -----------------------------------------------------------------------------
; umath_abs_f64 - scalar double-precision absolute value
; args:    xmm0 = input double (val)
; returns: xmm0 = absolute value of input double
; -----------------------------------------------------------------------------
global umath_abs_f64
umath_abs_f64:
    movapd  xmm1, [mask_abs_f64]
    andpd   xmm0, xmm1
    ret

; -----------------------------------------------------------------------------
; umath_abs_f64_array - compute absolute value for an array of doubles
; args:    rdi = destination pointer (dst)
;          rsi = source pointer (src)
;          rdx = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_abs_f64_array
umath_abs_f64_array:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done
    test    rdx, rdx
    jz      .done

    movapd  xmm15, [mask_abs_f64]

    cmp     rdx, 8
    jb      .single_doubles

    mov     rcx, rdx
    shr     rcx, 3              ; rcx = number of 8-double (64-byte) blocks

.loop_unrolled:
    movups  xmm0, [rsi]
    movups  xmm1, [rsi + 16]
    movups  xmm2, [rsi + 32]
    movups  xmm3, [rsi + 48]

    andpd   xmm0, xmm15
    andpd   xmm1, xmm15
    andpd   xmm2, xmm15
    andpd   xmm3, xmm15

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
    shr     rcx, 1              ; count of 2-double vectors

.loop_vector:
    movups  xmm0, [rsi]
    andpd   xmm0, xmm15
    movups  [rdi], xmm0
    add     rsi, 16
    add     rdi, 16
    dec     rcx
    jnz     .loop_vector

    and     rdx, 1
    jz      .done

.residuals:
    movsd   xmm0, [rsi]
    andsd   xmm0, xmm15
    movsd   [rdi], xmm0
    add     rsi, 8
    add     rdi, 8
    dec     rdx
    jnz     .residuals

.done:
    ret

; -----------------------------------------------------------------------------
; umath_abs_f64_inplace - compute in-place absolute value for doubles
; args:    rdi = buffer pointer (buf)
;          rsi = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_abs_f64_inplace
umath_abs_f64_inplace:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done

    movapd  xmm15, [mask_abs_f64]

    cmp     rsi, 8
    jb      .single_doubles

    mov     rcx, rsi
    shr     rcx, 3

.loop_unrolled:
    movups  xmm0, [rdi]
    movups  xmm1, [rdi + 16]
    movups  xmm2, [rdi + 32]
    movups  xmm3, [rdi + 48]

    andpd   xmm0, xmm15
    andpd   xmm1, xmm15
    andpd   xmm2, xmm15
    andpd   xmm3, xmm15

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
    andpd   xmm0, xmm15
    movups  [rdi], xmm0
    add     rdi, 16
    dec     rcx
    jnz     .loop_vector

    and     rsi, 1
    jz      .done

.residuals:
    movsd   xmm0, [rdi]
    andsd   xmm0, xmm15
    movsd   [rdi], xmm0
    add     rdi, 8
    dec     rsi
    jnz     .residuals

.done:
    ret

; -----------------------------------------------------------------------------
; umath_abs_f64_isnan - check if double-precision float is NaN
; args:    xmm0 = input double (val)
; returns: eax = 1 (is NaN) or 0 (is not NaN)
; -----------------------------------------------------------------------------
global umath_abs_f64_isnan
umath_abs_f64_isnan:
    ucomisd xmm0, xmm0
    setp    al
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_abs_f64_isinf - check if double-precision float is Infinity (+/- Inf)
; args:    xmm0 = input double (val)
; returns: eax = 1 (is Inf) or 0 (is not Inf)
; -----------------------------------------------------------------------------
global umath_abs_f64_isinf
umath_abs_f64_isinf:
    movq    rcx, xmm0
    movabs  rax, 0x7FFFFFFFFFFFFFFF
    and     rcx, rax
    movabs  rax, 0x7FF0000000000000
    cmp     rcx, rax
    sete    al
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_abs_f64_copysign - return absolute value of val with sign of sign_val
; args:    xmm0 = magnitude value (val)
;          xmm1 = sign value (sign_val)
; returns: xmm0 = absolute value of val with sign of sign_val
; -----------------------------------------------------------------------------
global umath_abs_f64_copysign
umath_abs_f64_copysign:
    movapd  xmm2, [mask_abs_f64]
    andpd   xmm0, xmm2
    andnpd  xmm2, xmm1
    orpd    xmm0, xmm2
    ret

; -----------------------------------------------------------------------------
; umath_abs_f64_count_negative - count how many elements in double array are negative
; args:    rdi = source pointer (src)
;          rsi = size of array (count)
; returns: rax = count of negative elements
; -----------------------------------------------------------------------------
global umath_abs_f64_count_negative
umath_abs_f64_count_negative:
    xor     rax, rax            ; count = 0
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done

    movaps  xmm15, [mask_sign_f64]

    cmp     rsi, 8
    jb      .single_doubles

    mov     rcx, rsi
    shr     rcx, 3

.loop_unrolled:
    movups  xmm0, [rdi]
    movups  xmm1, [rdi + 16]
    movups  xmm2, [rdi + 32]
    movups  xmm3, [rdi + 48]

    andpd   xmm0, xmm15
    andpd   xmm1, xmm15
    andpd   xmm2, xmm15
    andpd   xmm3, xmm15

    movmskpd edx, xmm0
    popcnt  edx, edx
    add     rax, rdx

    movmskpd edx, xmm1
    popcnt  edx, edx
    add     rax, rdx

    movmskpd edx, xmm2
    popcnt  edx, edx
    add     rax, rdx

    movmskpd edx, xmm3
    popcnt  edx, edx
    add     rax, rdx

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
    andpd   xmm0, xmm15
    movmskpd edx, xmm0
    popcnt  edx, edx
    add     rax, rdx
    add     rdi, 16
    dec     rcx
    jnz     .loop_vector

    and     rsi, 1
    jz      .done

.residuals:
    movsd   xmm0, [rdi]
    movq    rcx, xmm0
    test    rcx, rcx
    jns     .next_residual
    inc     rax

.next_residual:
    add     rdi, 8
    dec     rsi
    jnz     .residuals

.done:
    ret

; -----------------------------------------------------------------------------
; umath_abs_f64_is_all_positive - checks if all elements in double array are non-negative
; args:    rdi = source pointer (src)
;          rsi = size of array (count)
; returns: eax = 1 if all elements are positive or zero, 0 otherwise
; -----------------------------------------------------------------------------
global umath_abs_f64_is_all_positive
umath_abs_f64_is_all_positive:
    mov     eax, 1
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done

    movaps  xmm15, [mask_sign_f64]

    cmp     rsi, 8
    jb      .single_doubles

    mov     rcx, rsi
    shr     rcx, 3

.loop_unrolled:
    movups  xmm0, [rdi]
    movups  xmm1, [rdi + 16]
    movups  xmm2, [rdi + 32]
    movups  xmm3, [rdi + 48]

    orpd    xmm0, xmm1
    orpd    xmm2, xmm3
    orpd    xmm0, xmm2
    andpd   xmm0, xmm15

    movmskpd edx, xmm0
    test    edx, edx
    jnz     .not_all_positive

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
    andpd   xmm0, xmm15
    movmskpd edx, xmm0
    test    edx, edx
    jnz     .not_all_positive
    add     rdi, 16
    dec     rcx
    jnz     .loop_vector

    and     rsi, 1
    jz      .done

.residuals:
    movsd   xmm0, [rdi]
    movq    rcx, xmm0
    test    rcx, rcx
    js      .not_all_positive
    add     rdi, 8
    dec     rsi
    jnz     .residuals
    ret

.not_all_positive:
    xor     eax, eax
.done:
    ret
