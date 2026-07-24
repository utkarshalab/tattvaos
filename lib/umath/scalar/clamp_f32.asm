; =============================================================================
; umath - unified math library
; scalar/clamp_f32.asm - single-precision float clamp implementations
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; Performance Optimizations:
;   - Vectorized element-wise clamping unrolled 4x (using SSE minps/maxps).
;   - Dynamic array-based clamping boundaries.
;   - In-place and copying clamp mappings.
;   - Range verification helper with strict NaN handling.
;   - Counting clamped elements.
; =============================================================================

bits 64
section .text

; -----------------------------------------------------------------------------
; umath_clamp_f32 - clamp a scalar float value to [min_val, max_val]
; args:    xmm0 = input value (val)
;          xmm1 = minimum boundary (min_val)
;          xmm2 = maximum boundary (max_val)
; returns: xmm0 = clamped value
; -----------------------------------------------------------------------------
global umath_clamp_f32
umath_clamp_f32:
    minss   xmm0, xmm2          ; xmm0 = min(val, max_val)
    maxss   xmm0, xmm1          ; xmm0 = max(min(val, max_val), min_val)
    ret

; -----------------------------------------------------------------------------
; umath_clamp_f32_array - clamp an array of floats to constant boundary limits
; args:    rdi = destination pointer (dst)
;          rsi = source pointer (src)
;          rdx = size of array (count)
;          xmm0 = minimum boundary (min_val)
;          xmm1 = maximum boundary (max_val)
; returns: void
; -----------------------------------------------------------------------------
global umath_clamp_f32_array
umath_clamp_f32_array:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done
    test    rdx, rdx
    jz      .done

    ; Broadcast boundaries across all 4 slots of registers
    shufps  xmm0, xmm0, 0       ; xmm0 = [min_val, min_val, min_val, min_val]
    shufps  xmm1, xmm1, 0       ; xmm1 = [max_val, max_val, max_val, max_val]
    movaps  xmm14, xmm0         ; xmm14 = broadcasted min
    movaps  xmm15, xmm1         ; xmm15 = broadcasted max

    cmp     rdx, 16
    jb      .single_floats

    mov     rcx, rdx
    shr     rcx, 4              ; count of 16-float blocks

.loop_unrolled:
    ; Load 16 floats (4 xmm registers)
    movups  xmm0, [rsi]
    movups  xmm1, [rsi + 16]
    movups  xmm2, [rsi + 32]
    movups  xmm3, [rsi + 48]

    ; Clamp against max
    minps   xmm0, xmm15
    minps   xmm1, xmm15
    minps   xmm2, xmm15
    minps   xmm3, xmm15

    ; Clamp against min
    maxps   xmm0, xmm14
    maxps   xmm1, xmm14
    maxps   xmm2, xmm14
    maxps   xmm3, xmm14

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
    shr     rcx, 2              ; count of 4-float vectors

.loop_vector:
    movups  xmm0, [rsi]
    minps   xmm0, xmm15
    maxps   xmm0, xmm14
    movups  [rdi], xmm0
    add     rsi, 16
    add     rdi, 16
    dec     rcx
    jnz     .loop_vector

    and     rdx, 3
    jz      .done

.residuals:
    movss   xmm0, [rsi]
    minss   xmm0, xmm15
    maxss   xmm0, xmm14
    movss   [rdi], xmm0
    add     rsi, 4
    add     rdi, 4
    dec     rdx
    jnz     .residuals

.done:
    ret

; -----------------------------------------------------------------------------
; umath_clamp_f32_inplace - in-place clamping of a float array to constant boundaries
; args:    rdi = buffer pointer (buf)
;          rsi = size of array (count)
;          xmm0 = minimum boundary (min_val)
;          xmm1 = maximum boundary (max_val)
; returns: void
; -----------------------------------------------------------------------------
global umath_clamp_f32_inplace
umath_clamp_f32_inplace:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done

    shufps  xmm0, xmm0, 0
    shufps  xmm1, xmm1, 0
    movaps  xmm14, xmm0
    movaps  xmm15, xmm1

    cmp     rsi, 16
    jb      .single_floats

    mov     rcx, rsi
    shr     rcx, 4

.loop_unrolled:
    movups  xmm0, [rdi]
    movups  xmm1, [rdi + 16]
    movups  xmm2, [rdi + 32]
    movups  xmm3, [rdi + 48]

    minps   xmm0, xmm15
    minps   xmm1, xmm15
    minps   xmm2, xmm15
    minps   xmm3, xmm15

    maxps   xmm0, xmm14
    maxps   xmm1, xmm14
    maxps   xmm2, xmm14
    maxps   xmm3, xmm14

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
    minps   xmm0, xmm15
    maxps   xmm0, xmm14
    movups  [rdi], xmm0
    add     rdi, 16
    dec     rcx
    jnz     .loop_vector

    and     rsi, 3
    jz      .done

.residuals:
    movss   xmm0, [rdi]
    minss   xmm0, xmm15
    maxss   xmm0, xmm14
    movss   [rdi], xmm0
    add     rdi, 4
    dec     rsi
    jnz     .residuals

.done:
    ret

; -----------------------------------------------------------------------------
; umath_clamp_f32_is_in_range - check if a float value is within range [min_val, max_val]
; args:    xmm0 = input value (val)
;          xmm1 = minimum boundary (min_val)
;          xmm2 = maximum boundary (max_val)
; returns: eax = 1 if val is in range, 0 if out of range or NaN
; -----------------------------------------------------------------------------
global umath_clamp_f32_is_in_range
umath_clamp_f32_is_in_range:
    ; Compare val vs min_val
    ucomiss xmm0, xmm1
    jb      .out_of_range       ; val < min_val, or unordered (NaN)
    jp      .out_of_range       ; NaN guard

    ; Compare val vs max_val
    ucomiss xmm2, xmm0
    jb      .out_of_range       ; max_val < val, or unordered (NaN)
    jp      .out_of_range       ; NaN guard

    mov     eax, 1              ; True
    ret

.out_of_range:
    xor     eax, eax            ; False
    ret

; -----------------------------------------------------------------------------
; umath_clamp_f32_array_inplace_dynamic - clamp an array of floats using dynamic array limits
; args:    rdi = destination/source array pointer (dst_src)
;          rsi = min boundaries array pointer (min_arr)
;          rdx = max boundaries array pointer (max_arr)
;          rcx = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_clamp_f32_array_inplace_dynamic
umath_clamp_f32_array_inplace_dynamic:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done
    test    rdx, rdx
    jz      .done
    test    rcx, rcx
    jz      .done

    cmp     rcx, 16
    jb      .single_floats

    mov     r8, rcx
    shr     r8, 4

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
    minps   xmm0, xmm8
    minps   xmm1, xmm9
    minps   xmm2, xmm10
    minps   xmm3, xmm11

    ; dst = max(dst, min_val)
    maxps   xmm0, xmm4
    maxps   xmm1, xmm5
    maxps   xmm2, xmm6
    maxps   xmm3, xmm7

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

    and     rcx, 15
    jz      .done

.single_floats:
    cmp     rcx, 4
    jb      .residuals

    mov     r8, rcx
    shr     r8, 2

.loop_vector:
    movups  xmm0, [rdi]
    movups  xmm1, [rsi]
    movups  xmm2, [rdx]

    minps   xmm0, xmm2
    maxps   xmm0, xmm1
    movups  [rdi], xmm0

    add     rdi, 16
    add     rsi, 16
    add     rdx, 16
    dec     r8
    jnz     .loop_vector

    and     rcx, 3
    jz      .done

.residuals:
    movss   xmm0, [rdi]
    movss   xmm1, [rsi]
    movss   xmm2, [rdx]

    minss   xmm0, xmm2
    maxss   xmm0, xmm1
    movss   [rdi], xmm0

    add     rdi, 4
    add     rsi, 4
    add     rdx, 4
    dec     rcx
    jnz     .residuals

.done:
    ret

; -----------------------------------------------------------------------------
; umath_clamp_f32_count_clamped - count how many elements in array fall outside [min_val, max_val]
; args:    rdi = source pointer (src)
;          rsi = size of array (count)
;          xmm0 = minimum boundary (min_val)
;          xmm1 = maximum boundary (max_val)
; returns: rax = count of elements clamped
; -----------------------------------------------------------------------------
global umath_clamp_f32_count_clamped
umath_clamp_f32_count_clamped:
    xor     rax, rax            ; clamped_count = 0
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done

    shufps  xmm0, xmm0, 0
    shufps  xmm1, xmm1, 0
    movaps  xmm14, xmm0         ; xmm14 = min_val
    movaps  xmm15, xmm1         ; xmm15 = max_val

    cmp     rsi, 16
    jb      .single_floats

    mov     rcx, rsi
    shr     rcx, 4

.loop_unrolled:
    movups  xmm0, [rdi]
    movups  xmm1, [rdi + 16]
    movups  xmm2, [rdi + 32]
    movups  xmm3, [rdi + 48]

    ; Check if under min_val
    ; cmpltps returns 0xFFFFFFFF if val < min_val
    movups  xmm4, xmm0
    movups  xmm5, xmm1
    movups  xmm6, xmm2
    movups  xmm7, xmm3

    cmpltps xmm4, xmm14
    cmpltps xmm5, xmm14
    cmpltps xmm6, xmm14
    cmpltps xmm7, xmm14

    ; Check if over max_val
    ; cmpgtps is not standard in SSE, but cmpltps with swapped arguments works: val > max_val <=> max_val < val
    movups  xmm8, xmm15
    movups  xmm9, xmm15
    movups  xmm10, xmm15
    movups  xmm11, xmm15

    cmpltps xmm8, xmm0
    cmpltps xmm9, xmm1
    cmpltps xmm10, xmm2
    cmpltps xmm11, xmm3

    ; Combine masks (under OR over)
    orps    xmm4, xmm8
    orps    xmm5, xmm9
    orps    xmm6, xmm10
    orps    xmm7, xmm11

    ; Now extract signs of masks to count bits set
    ; movmskps extracts the sign bit of each of the 4 elements into a 4-bit integer
    movmskps edx, xmm4
    ; Count set bits in edx (using popcnt)
    popcnt  edx, edx
    add     rax, rdx

    movmskps edx, xmm5
    popcnt  edx, edx
    add     rax, rdx

    movmskps edx, xmm6
    popcnt  edx, edx
    add     rax, rdx

    movmskps edx, xmm7
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
    movups  xmm1, xmm0
    movups  xmm2, xmm15

    cmpltps xmm1, xmm14         ; val < min
    cmpltps xmm2, xmm0          ; max < val
    orps    xmm1, xmm2          ; either

    movmskps edx, xmm1
    popcnt  edx, edx
    add     rax, rdx

    add     rdi, 16
    dec     rcx
    jnz     .loop_vector

    and     rsi, 3
    jz      .done

.residuals:
    movss   xmm0, [rdi]
    ucomiss xmm0, xmm14
    jb      .is_clamped
    ucomiss xmm15, xmm0
    jb      .is_clamped
    jmp     .next_residual

.is_clamped:
    inc     rax

.next_residual:
    add     rdi, 4
    dec     rsi
    jnz     .residuals

.done:
    ret
