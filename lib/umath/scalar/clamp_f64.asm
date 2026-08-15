%ifndef GUARD_LIB_UMATH_SCALAR_CLAMP_F64_ASM
%define GUARD_LIB_UMATH_SCALAR_CLAMP_F64_ASM
; =============================================================================
; umath - unified math library
; scalar/clamp_f64.asm - double-precision float clamp implementations
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; Performance Optimizations:
;   - Vectorized element-wise clamping unrolled 4x (using SSE2 minpd/maxpd).
;   - Dynamic array-based clamping boundaries.
;   - In-place and copying clamp mappings.
;   - Range verification helper with strict NaN handling.
;   - Counting clamped elements with popcnt.
; =============================================================================

bits 64
section .text

; -----------------------------------------------------------------------------
; umath_clamp_f64 - clamp a scalar double value to [min_val, max_val]
; args:    xmm0 = input value (val)
;          xmm1 = minimum boundary (min_val)
;          xmm2 = maximum boundary (max_val)
; returns: xmm0 = clamped value
; -----------------------------------------------------------------------------
global umath_clamp_f64
umath_clamp_f64:
    minsd   xmm0, xmm2          ; xmm0 = min(val, max_val)
    maxsd   xmm0, xmm1          ; xmm0 = max(min(val, max_val), min_val)
    ret

; -----------------------------------------------------------------------------
; umath_clamp_f64_array - clamp an array of doubles to constant boundary limits
; args:    rdi = destination pointer (dst)
;          rsi = source pointer (src)
;          rdx = size of array (count)
;          xmm0 = minimum boundary (min_val)
;          xmm1 = maximum boundary (max_val)
; returns: void
; -----------------------------------------------------------------------------
global umath_clamp_f64_array
umath_clamp_f64_array:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done
    test    rdx, rdx
    jz      .done

    ; Broadcast boundaries across both lanes of 128-bit registers (each holds 2 doubles)
    unpcklpd xmm0, xmm0         ; xmm0 = [min_val, min_val]
    unpcklpd xmm1, xmm1         ; xmm1 = [max_val, max_val]
    movapd  xmm14, xmm0         ; xmm14 = broadcasted min
    movapd  xmm15, xmm1         ; xmm15 = broadcasted max

    ; If count < 8, skip unrolled vectorized loop (8 elements of 8 bytes = 64 bytes)
    cmp     rdx, 8
    jb      .single_doubles

    mov     rcx, rdx
    shr     rcx, 3              ; count of 8-double blocks

.loop_unrolled:
    ; Load 8 doubles (4 xmm registers)
    movups  xmm0, [rsi]
    movups  xmm1, [rsi + 16]
    movups  xmm2, [rsi + 32]
    movups  xmm3, [rsi + 48]

    ; Clamp against max
    minpd   xmm0, xmm15
    minpd   xmm1, xmm15
    minpd   xmm2, xmm15
    minpd   xmm3, xmm15

    ; Clamp against min
    maxpd   xmm0, xmm14
    maxpd   xmm1, xmm14
    maxpd   xmm2, xmm14
    maxpd   xmm3, xmm14

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
    shr     rcx, 1              ; count of 2-double vectors

.loop_vector:
    movups  xmm0, [rsi]
    minpd   xmm0, xmm15
    maxpd   xmm0, xmm14
    movups  [rdi], xmm0
    add     rsi, 16
    add     rdi, 16
    dec     rcx
    jnz     .loop_vector

    and     rdx, 1
    jz      .done

.residuals:
    movsd   xmm0, [rsi]
    minsd   xmm0, xmm15
    maxsd   xmm0, xmm14
    movsd   [rdi], xmm0
    add     rsi, 8
    add     rdi, 8
    dec     rdx
    jnz     .residuals

.done:
    ret

; -----------------------------------------------------------------------------
; umath_clamp_f64_inplace - in-place clamping of a double array to constant boundaries
; args:    rdi = buffer pointer (buf)
;          rsi = size of array (count)
;          xmm0 = minimum boundary (min_val)
;          xmm1 = maximum boundary (max_val)
; returns: void
; -----------------------------------------------------------------------------
global umath_clamp_f64_inplace
umath_clamp_f64_inplace:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done

    unpcklpd xmm0, xmm0
    unpcklpd xmm1, xmm1
    movapd  xmm14, xmm0
    movapd  xmm15, xmm1

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

    maxpd   xmm0, xmm14
    maxpd   xmm1, xmm14
    maxpd   xmm2, xmm14
    maxpd   xmm3, xmm14

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
    minpd   xmm0, xmm15
    maxpd   xmm0, xmm14
    movups  [rdi], xmm0
    add     rdi, 16
    dec     rcx
    jnz     .loop_vector

    and     rsi, 1
    jz      .done

.residuals:
    movsd   xmm0, [rdi]
    minsd   xmm0, xmm15
    maxsd   xmm0, xmm14
    movsd   [rdi], xmm0
    add     rdi, 8
    dec     rsi
    jnz     .residuals

.done:
    ret

; -----------------------------------------------------------------------------
; umath_clamp_f64_is_in_range - check if a double value is within range [min_val, max_val]
; args:    xmm0 = input value (val)
;          xmm1 = minimum boundary (min_val)
;          xmm2 = maximum boundary (max_val)
; returns: eax = 1 if val is in range, 0 if out of range or NaN
; -----------------------------------------------------------------------------
global umath_clamp_f64_is_in_range
umath_clamp_f64_is_in_range:
    ucomisd xmm0, xmm1
    jb      .out_of_range       ; val < min_val, or unordered (NaN)
    jp      .out_of_range       ; NaN guard

    ucomisd xmm2, xmm0
    jb      .out_of_range       ; max_val < val, or unordered (NaN)
    jp      .out_of_range       ; NaN guard

    mov     eax, 1              ; True
    ret

.out_of_range:
    xor     eax, eax            ; False
    ret

; -----------------------------------------------------------------------------
; umath_clamp_f64_array_inplace_dynamic - clamp an array of doubles using dynamic array limits
; args:    rdi = destination/source array pointer (dst_src)
;          rsi = min boundaries array pointer (min_arr)
;          rdx = max boundaries array pointer (max_arr)
;          rcx = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_clamp_f64_array_inplace_dynamic
umath_clamp_f64_array_inplace_dynamic:
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
    shr     r8, 3

.loop_unrolled:
    movups  xmm0, [rdi]
    movups  xmm1, [rdi + 16]
    movups  xmm2, [rdi + 32]
    movups  xmm3, [rdi + 48]

    movups  xmm4, [rsi]
    movups  xmm5, [rsi + 16]
    movups  xmm6, [rsi + 32]
    movups  xmm7, [rsi + 48]

    movups  xmm8, [rdx]
    movups  xmm9, [rdx + 16]
    movups  xmm10, [rdx + 32]
    movups  xmm11, [rdx + 48]

    ; dst = min(dst, max_val)
    minpd   xmm0, xmm8
    minpd   xmm1, xmm9
    minpd   xmm2, xmm10
    minpd   xmm3, xmm11

    ; dst = max(dst, min_val)
    maxpd   xmm0, xmm4
    maxpd   xmm1, xmm5
    maxpd   xmm2, xmm6
    maxpd   xmm3, xmm7

    ; Store results
    movups  [rdi], xmm0
    movups  [rdi + 16], xmm1
    movups  [rdi + 32], xmm2
    movups  [rdi + 48], xmm3

    add     rdi, 64
    add     rsi, 64
    add     rdx, 64
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
    movups  xmm0, [rdi]
    movups  xmm1, [rsi]
    movups  xmm2, [rdx]

    minpd   xmm0, xmm2
    maxpd   xmm0, xmm1
    movups  [rdi], xmm0

    add     rdi, 16
    add     rsi, 16
    add     rdx, 16
    dec     r8
    jnz     .loop_vector

    and     rcx, 1
    jz      .done

.residuals:
    movsd   xmm0, [rdi]
    movsd   xmm1, [rsi]
    movsd   xmm2, [rdx]

    minsd   xmm0, xmm2
    maxsd   xmm0, xmm1
    movsd   [rdi], xmm0

    add     rdi, 8
    add     rsi, 8
    add     rdx, 8
    dec     rcx
    jnz     .residuals

.done:
    ret

; -----------------------------------------------------------------------------
; umath_clamp_f64_count_clamped - count how many elements in array fall outside [min_val, max_val]
; args:    rdi = source pointer (src)
;          rsi = size of array (count)
;          xmm0 = minimum boundary (min_val)
;          xmm1 = maximum boundary (max_val)
; returns: rax = count of elements clamped
; -----------------------------------------------------------------------------
global umath_clamp_f64_count_clamped
umath_clamp_f64_count_clamped:
    xor     rax, rax            ; clamped_count = 0
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done

    unpcklpd xmm0, xmm0
    unpcklpd xmm1, xmm1
    movapd  xmm14, xmm0         ; xmm14 = min_val
    movapd  xmm15, xmm1         ; xmm15 = max_val

    cmp     rsi, 8
    jb      .single_doubles

    mov     rcx, rsi
    shr     rcx, 3

.loop_unrolled:
    movups  xmm0, [rdi]
    movups  xmm1, [rdi + 16]
    movups  xmm2, [rdi + 32]
    movups  xmm3, [rdi + 48]

    ; Check if under min_val
    movups  xmm4, xmm0
    movups  xmm5, xmm1
    movups  xmm6, xmm2
    movups  xmm7, xmm3

    cmpltpd xmm4, xmm14
    cmpltpd xmm5, xmm14
    cmpltpd xmm6, xmm14
    cmpltpd xmm7, xmm14

    ; Check if over max_val
    movups  xmm8, xmm15
    movups  xmm9, xmm15
    movups  xmm10, xmm15
    movups  xmm11, xmm15

    cmpltpd xmm8, xmm0
    cmpltpd xmm9, xmm1
    cmpltpd xmm10, xmm2
    cmpltpd xmm11, xmm3

    ; Combine masks (under OR over)
    orpd    xmm4, xmm8
    orpd    xmm5, xmm9
    orpd    xmm6, xmm10
    orpd    xmm7, xmm11

    ; Extract signs of masks for doubles (movmskpd extracts 2 bits per register)
    movmskpd edx, xmm4
    popcnt  edx, edx
    add     rax, rdx

    movmskpd edx, xmm5
    popcnt  edx, edx
    add     rax, rdx

    movmskpd edx, xmm6
    popcnt  edx, edx
    add     rax, rdx

    movmskpd edx, xmm7
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
    movups  xmm1, xmm0
    movups  xmm2, xmm15

    cmpltpd xmm1, xmm14         ; val < min
    cmpltpd xmm2, xmm0          ; max < val
    orpd    xmm1, xmm2          ; either

    movmskpd edx, xmm1
    popcnt  edx, edx
    add     rax, rdx

    add     rdi, 16
    dec     rcx
    jnz     .loop_vector

    and     rsi, 1
    jz      .done

.residuals:
    movsd   xmm0, [rdi]
    ucomisd xmm0, xmm14
    jb      .is_clamped
    ucomisd xmm15, xmm0
    jb      .is_clamped
    jmp     .next_residual

.is_clamped:
    inc     rax

.next_residual:
    add     rdi, 8
    dec     rsi
    jnz     .residuals

.done:
    ret

%endif ; GUARD_LIB_UMATH_SCALAR_CLAMP_F64_ASM
