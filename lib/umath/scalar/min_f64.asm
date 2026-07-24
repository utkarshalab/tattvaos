; =============================================================================
; umath - unified math library
; scalar/min_f64.asm - double-precision float minimum implementations
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; IEEE 754 Minimum Specification:
;   - Standard minimum: return b if b < a, else a.
;   - Strict IEEE-754 minimum (umath_min_f64_ieee):
;     1. NaN Propagation: if one operand is NaN and the other is a number,
;        the number must be returned. If both are NaN, return NaN.
;     2. Signed Zeros: -0.0 is defined as strictly less than +0.0.
;        If inputs are +0.0 and -0.0, the minimum must return -0.0.
;
; Performance Optimizations:
;   - Vectorized element-wise minimums unrolled 4x.
;   - Argument reduction (argmin index) with branchless checks.
;   - Inplace clamping/clipping for activation functions.
; =============================================================================

bits 64
section .text

; 128-bit absolute value mask (clears bit 63 of each 64-bit slot)
align 16
mask_abs_f64:
    dq 0x7FFFFFFFFFFFFFFF, 0x7FFFFFFFFFFFFFFF

; -----------------------------------------------------------------------------
; umath_min_f64 - scalar double-precision float minimum
; args:    xmm0 = a
;          xmm1 = b
; returns: xmm0 = min(a, b)
; -----------------------------------------------------------------------------
global umath_min_f64
umath_min_f64:
    minsd   xmm0, xmm1
    ret

; -----------------------------------------------------------------------------
; umath_min_f64_ieee - strict IEEE-754 compliant double minimum
; args:    xmm0 = a
;          xmm1 = b
; returns: xmm0 = min(a, b) matching NaN propagation and signed zero rules
; -----------------------------------------------------------------------------
global umath_min_f64_ieee
umath_min_f64_ieee:
    ucomisd xmm0, xmm1
    jp      .handle_nan         ; Parity flag set implies unordered (NaN)

    ucomisd xmm0, xmm1
    jb      .a_smaller          ; a < b -> return a
    ja      .b_smaller          ; a > b -> return b

    ; Bitwise OR: if either is -0.0, the OR result will set the sign bit, returning -0.0
    orpd    xmm0, xmm1
    ret

.a_smaller:
    ret

.b_smaller:
    movsd   xmm0, xmm1
    ret

.handle_nan:
    ucomisd xmm0, xmm0
    jp      .a_is_nan           ; a is NaN

    ret

.a_is_nan:
    ucomisd xmm1, xmm1
    jp      .both_nan

    movsd   xmm0, xmm1
    ret

.both_nan:
    ret

; -----------------------------------------------------------------------------
; umath_min_f64_array - compute element-wise minimum of two double arrays
; args:    rdi = destination pointer (dst)
;          rsi = source pointer a (src_a)
;          rdx = source pointer b (src_b)
;          rcx = size of arrays (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_min_f64_array
umath_min_f64_array:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done
    test    rdx, rdx
    jz      .done
    test    rcx, rcx
    jz      .done

    cmp     rcx, 8
    jb      .single_doubles

    mov     r8, rcx
    shr     r8, 3               ; count of 8-double (64-byte) blocks

.loop_unrolled:
    movups  xmm0, [rsi]
    movups  xmm1, [rsi + 16]
    movups  xmm2, [rsi + 32]
    movups  xmm3, [rsi + 48]

    movups  xmm4, [rdx]
    movups  xmm5, [rdx + 16]
    movups  xmm6, [rdx + 32]
    movups  xmm7, [rdx + 48]

    minpd   xmm0, xmm4
    minpd   xmm1, xmm5
    minpd   xmm2, xmm6
    minpd   xmm3, xmm7

    movups  [rdi], xmm0
    movups  [rdi + 16], xmm1
    movups  [rdi + 32], xmm2
    movups  [rdi + 48], xmm3

    add     rsi, 64
    add     rdx, 64
    add     rdi, 64
    dec     r8
    jnz     .loop_unrolled

    and     rcx, 7
    jz      .done

.single_doubles:
    cmp     rcx, 2
    jb      .residuals

    mov     r8, rcx
    shr     r8, 1

.loop_vector:
    movups  xmm0, [rsi]
    movups  xmm1, [rdx]
    minpd   xmm0, xmm1
    movups  [rdi], xmm0
    add     rsi, 16
    add     rdx, 16
    add     rdi, 16
    dec     r8
    jnz     .loop_vector

    and     rcx, 1
    jz      .done

.residuals:
    movsd   xmm0, [rsi]
    movsd   xmm1, [rdx]
    minsd   xmm0, xmm1
    movsd   [rdi], xmm0
    add     rsi, 8
    add     rdx, 8
    add     rdi, 8
    dec     rcx
    jnz     .residuals

.done:
    ret

; -----------------------------------------------------------------------------
; umath_min_f64_array_inplace - compute in-place element-wise minimum of two arrays
; args:    rdi = destination/source array pointer (dst_src)
;          rsi = source pointer b (src_b)
;          rdx = size of arrays (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_min_f64_array_inplace
umath_min_f64_array_inplace:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done
    test    rdx, rdx
    jz      .done

    cmp     rdx, 8
    jb      .single_doubles

    mov     rcx, rdx
    shr     rcx, 3

.loop_unrolled:
    movups  xmm0, [rdi]
    movups  xmm1, [rdi + 16]
    movups  xmm2, [rdi + 32]
    movups  xmm3, [rdi + 48]

    movups  xmm4, [rsi]
    movups  xmm5, [rsi + 16]
    movups  xmm6, [rsi + 32]
    movups  xmm7, [rsi + 48]

    minpd   xmm0, xmm4
    minpd   xmm1, xmm5
    minpd   xmm2, xmm6
    minpd   xmm3, xmm7

    movups  [rdi], xmm0
    movups  [rdi + 16], xmm1
    movups  [rdi + 32], xmm2
    movups  [rdi + 48], xmm3

    add     rdi, 64
    add     rsi, 64
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
    movups  xmm0, [rdi]
    movups  xmm1, [rsi]
    minpd   xmm0, xmm1
    movups  [rdi], xmm0
    add     rdi, 16
    add     rsi, 16
    dec     rcx
    jnz     .loop_vector

    and     rdx, 1
    jz      .done

.residuals:
    movsd   xmm0, [rdi]
    movsd   xmm1, [rsi]
    minsd   xmm0, xmm1
    movsd   [rdi], xmm0
    add     rdi, 8
    add     rsi, 8
    dec     rdx
    jnz     .residuals

.done:
    ret

; -----------------------------------------------------------------------------
; umath_min_f64_reduce - reduce an array of doubles to its minimum value
; args:    rdi = source pointer (src)
;          rsi = size of array (count)
; returns: xmm0 = minimum double value in array (returns NaN if any element is NaN)
; -----------------------------------------------------------------------------
global umath_min_f64_reduce
umath_min_f64_reduce:
    xorps   xmm0, xmm0
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done

    movsd   xmm0, [rdi]
    add     rdi, 8
    dec     rsi
    jz      .done

.loop_reduce:
    movsd   xmm1, [rdi]
    minsd   xmm0, xmm1
    add     rdi, 8
    dec     rsi
    jnz     .loop_reduce
.done:
    ret

; -----------------------------------------------------------------------------
; umath_min_f64_reduce_index - reduce array of doubles to index of minimum (argmin)
; args:    rdi = source pointer (src)
;          rsi = size of array (count)
; returns: rax = index of first occurrence of the minimum value, or -1 if empty
; -----------------------------------------------------------------------------
global umath_min_f64_reduce_index
umath_min_f64_reduce_index:
    mov     rax, -1
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done

    xor     rax, rax            ; min_index = 0
    movsd   xmm0, [rdi]         ; min_val = src[0]
    
    mov     rcx, 1
    dec     rsi
    jz      .done

.loop_reduce:
    movsd   xmm1, [rdi + rcx * 8]
    
    ucomisd xmm1, xmm0
    jae     .next_item
    jp      .next_item          ; skip NaN

    movsd   xmm0, xmm1
    mov     rax, rcx

.next_item:
    inc     rcx
    dec     rsi
    jnz     .loop_reduce

.done:
    ret

; -----------------------------------------------------------------------------
; umath_min_f64_inplace_clip - clips elements in-place to not exceed threshold (top limit)
; args:    rdi = buffer pointer (buf)
;          rsi = size of array (count)
;          xmm0 = threshold value
; returns: void
; -----------------------------------------------------------------------------
global umath_min_f64_inplace_clip
umath_min_f64_inplace_clip:
    test    rdi, rdi
    jz      .done_clip
    test    rsi, rsi
    jz      .done_clip

    unpcklpd xmm0, xmm0
    movapd  xmm15, xmm0

    cmp     rsi, 8
    jb      .single_doubles

    mov     rcx, rsi
    shr     rcx, 3

.loop_unrolled:
    movups  xmm0, [rdi]
    movups  xmm1, [rdi + 16]
    movups  xmm2, [rdi + 32]
    movups  xmm3, [rdi + 48]

    minpd   xmm0, xmm15
    minpd   xmm1, xmm15
    minpd   xmm2, xmm15
    minpd   xmm3, xmm15

    movups  [rdi], xmm0
    movups  [rdi + 16], xmm1
    movups  [rdi + 32], xmm2
    movups  [rdi + 48], xmm3

    add     rdi, 64
    dec     rcx
    jnz     .loop_unrolled

    and     rsi, 7
    jz      .done_clip

.single_doubles:
    cmp     rsi, 2
    jb      .residuals

    mov     rcx, rsi
    shr     rcx, 1

.loop_vector:
    movups  xmm0, [rdi]
    minpd   xmm0, xmm15
    movups  [rdi], xmm0
    add     rdi, 16
    dec     rcx
    jnz     .loop_vector

    and     rsi, 1
    jz      .done_clip

.residuals:
    movsd   xmm0, [rdi]
    minsd   xmm0, xmm15
    movsd   [rdi], xmm0
    add     rdi, 8
    dec     rsi
    jnz     .residuals

.done_clip:
    ret

; -----------------------------------------------------------------------------
; umath_min_f64_reduce_range - reduce sub-segment of array to its minimum value
; args:    rdi = source pointer (src)
;          rsi = start index
;          rdx = end index (exclusive)
; returns: xmm0 = minimum value in range, or 0 if invalid
; -----------------------------------------------------------------------------
global umath_min_f64_reduce_range
umath_min_f64_reduce_range:
    xorps   xmm0, xmm0
    test    rdi, rdi
    jz      .done_range
    cmp     rsi, rdx
    jae     .done_range         ; invalid range

    mov     rcx, rdx
    sub     rcx, rsi

    lea     rdi, [rdi + rsi * 8]

    movsd   xmm0, [rdi]
    add     rdi, 8
    dec     rcx
    jz      .done_range

.loop_reduce:
    movsd   xmm1, [rdi]
    minsd   xmm0, xmm1
    add     rdi, 8
    dec     rcx
    jnz     .loop_reduce

.done_range:
    ret
