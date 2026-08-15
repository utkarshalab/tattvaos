%ifndef GUARD_LIB_UMATH_SCALAR_CLAMP_I32_ASM
%define GUARD_LIB_UMATH_SCALAR_CLAMP_I32_ASM
; =============================================================================
; umath - unified math library
; scalar/clamp_i32.asm - signed 32-bit integer clamp implementations
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; Performance Optimizations:
;   - Vectorized element-wise clamping unrolled 4x (using SSE4.1 pminsd/pmaxsd).
;   - Dynamic array-based clamping boundaries.
;   - In-place and copying clamp mappings.
;   - Range verification helper using branchless sets/movzx.
;   - Counting clamped elements with pcmpgtd and movmskps.
; =============================================================================

bits 64
section .text

; -----------------------------------------------------------------------------
; umath_clamp_i32 - clamp a scalar signed 32-bit integer value to [min_val, max_val]
; args:    edi = input value (val)
;          esi = minimum boundary (min_val)
;          edx = maximum boundary (max_val)
; returns: eax = clamped value
; -----------------------------------------------------------------------------
global umath_clamp_i32
umath_clamp_i32:
    mov     eax, edi            ; eax = val
    cmp     edi, edx            ; compare val vs max_val
    cmovg   eax, edx            ; if val > max_val, eax = max_val
    cmp     eax, esi            ; compare clamped vs min_val
    cmovl   eax, esi            ; if clamped < min_val, eax = min_val
    ret

; -----------------------------------------------------------------------------
; umath_clamp_i32_array - clamp an array of signed 32-bit ints to constant boundary limits
; args:    rdi = destination pointer (dst)
;          rsi = source pointer (src)
;          rdx = size of array (count)
;          ecx = minimum boundary (min_val)
;          r8d = maximum boundary (max_val)
; returns: void
; -----------------------------------------------------------------------------
global umath_clamp_i32_array
umath_clamp_i32_array:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done
    test    rdx, rdx
    jz      .done

    ; Broadcast boundaries to XMM registers
    movd    xmm14, ecx
    pshufd  xmm14, xmm14, 0     ; xmm14 = [min_val, min_val, min_val, min_val]
    movd    xmm15, r8d
    pshufd  xmm15, xmm15, 0     ; xmm15 = [max_val, max_val, max_val, max_val]

    cmp     rdx, 16
    jb      .single_ints

    mov     rcx, rdx
    shr     rcx, 4              ; count of 16-integer blocks

.loop_unrolled:
    ; Load 16 integers (4 xmm registers)
    movups  xmm0, [rsi]
    movups  xmm1, [rsi + 16]
    movups  xmm2, [rsi + 32]
    movups  xmm3, [rsi + 48]

    ; Clamp against max: elements = min(elements, max_val) (SSE4.1 pminsd)
    pminsd  xmm0, xmm15
    pminsd  xmm1, xmm15
    pminsd  xmm2, xmm15
    pminsd  xmm3, xmm15

    ; Clamp against min: elements = max(elements, min_val) (SSE4.1 pmaxsd)
    pmaxsd  xmm0, xmm14
    pmaxsd  xmm1, xmm14
    pmaxsd  xmm2, xmm14
    pmaxsd  xmm3, xmm14

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

.single_ints:
    cmp     rdx, 4
    jb      .residuals

    mov     rcx, rdx
    shr     rcx, 2              ; count of 4-integer vectors

.loop_vector:
    movups  xmm0, [rsi]
    pminsd  xmm0, xmm15
    pmaxsd  xmm0, xmm14
    movups  [rdi], xmm0
    add     rsi, 16
    add     rdi, 16
    dec     rcx
    jnz     .loop_vector

    and     rdx, 3
    jz      .done

.residuals:
    mov     eax, [rsi]
    cmp     eax, r8d
    cmovg   eax, r8d
    cmp     eax, ecx
    cmovl   eax, ecx
    mov     [rdi], eax
    add     rsi, 4
    add     rdi, 4
    dec     rdx
    jnz     .residuals

.done:
    ret

; -----------------------------------------------------------------------------
; umath_clamp_i32_inplace - in-place clamping of a signed 32-bit int array
; args:    rdi = buffer pointer (buf)
;          rsi = size of array (count)
;          edx = minimum boundary (min_val)
;          ecx = maximum boundary (max_val)
; returns: void
; -----------------------------------------------------------------------------
global umath_clamp_i32_inplace
umath_clamp_i32_inplace:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done

    movd    xmm14, edx
    pshufd  xmm14, xmm14, 0
    movd    xmm15, ecx
    pshufd  xmm15, xmm15, 0

    cmp     rsi, 16
    jb      .single_ints

    mov     rcx, rsi
    shr     rcx, 4

.loop_unrolled:
    movups  xmm0, [rdi]
    movups  xmm1, [rdi + 16]
    movups  xmm2, [rdi + 32]
    movups  xmm3, [rdi + 48]

    pminsd  xmm0, xmm15
    pminsd  xmm1, xmm15
    pminsd  xmm2, xmm15
    pminsd  xmm3, xmm15

    pmaxsd  xmm0, xmm14
    pmaxsd  xmm1, xmm14
    pmaxsd  xmm2, xmm14
    pmaxsd  xmm3, xmm14

    movups  [rdi], xmm0
    movups  [rdi + 16], xmm1
    movups  [rdi + 32], xmm2
    movups  [rdi + 48], xmm3

    add     rdi, 64
    dec     rcx
    jnz     .loop_unrolled

    and     rsi, 15
    jz      .done

.single_ints:
    cmp     rsi, 4
    jb      .residuals

    mov     rcx, rsi
    shr     rcx, 2

.loop_vector:
    movups  xmm0, [rdi]
    pminsd  xmm0, xmm15
    pmaxsd  xmm0, xmm14
    movups  [rdi], xmm0
    add     rdi, 16
    dec     rcx
    jnz     .loop_vector

    and     rsi, 3
    jz      .done

.residuals:
    mov     eax, [rdi]
    cmp     eax, ecx
    cmovg   eax, ecx
    cmp     eax, edx
    cmovl   eax, edx
    mov     [rdi], eax
    add     rdi, 4
    dec     rsi
    jnz     .residuals

.done:
    ret

; -----------------------------------------------------------------------------
; umath_clamp_i32_is_in_range - check if a signed 32-bit int is within range [min_val, max_val]
; args:    edi = input value (val)
;          esi = minimum boundary (min_val)
;          edx = maximum boundary (max_val)
; returns: eax = 1 if val is in range, 0 otherwise
; -----------------------------------------------------------------------------
global umath_clamp_i32_is_in_range
umath_clamp_i32_is_in_range:
    xor     eax, eax
    cmp     edi, esi
    jl      .out_of_range       ; val < min_val
    cmp     edi, edx
    jg      .out_of_range       ; val > max_val

    mov     eax, 1
.out_of_range:
    ret

; -----------------------------------------------------------------------------
; umath_clamp_i32_array_inplace_dynamic - clamp an array of ints using dynamic array limits
; args:    rdi = destination/source array pointer (dst_src)
;          rsi = min boundaries array pointer (min_arr)
;          rdx = max boundaries array pointer (max_arr)
;          rcx = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_clamp_i32_array_inplace_dynamic
umath_clamp_i32_array_inplace_dynamic:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done
    test    rdx, rdx
    jz      .done
    test    rcx, rcx
    jz      .done

    cmp     rcx, 16
    jb      .single_ints

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
    pminsd  xmm0, xmm8
    pminsd  xmm1, xmm9
    pminsd  xmm2, xmm10
    pminsd  xmm3, xmm11

    ; dst = max(dst, min_val)
    pmaxsd  xmm0, xmm4
    pmaxsd  xmm1, xmm5
    pmaxsd  xmm2, xmm6
    pmaxsd  xmm3, xmm7

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

.single_ints:
    cmp     rcx, 4
    jb      .residuals

    mov     r8, rcx
    shr     r8, 2

.loop_vector:
    movups  xmm0, [rdi]
    movups  xmm1, [rsi]
    movups  xmm2, [rdx]

    pminsd  xmm0, xmm2
    pmaxsd  xmm0, xmm1
    movups  [rdi], xmm0

    add     rdi, 16
    add     rsi, 16
    add     rdx, 16
    dec     r8
    jnz     .loop_vector

    and     rcx, 3
    jz      .done

.residuals:
    mov     eax, [rdi]
    mov     r8d, [rsi]
    mov     r9d, [rdx]

    cmp     eax, r9d
    cmovg   eax, r9d
    cmp     eax, r8d
    cmovl   eax, r8d
    mov     [rdi], eax

    add     rdi, 4
    add     rsi, 4
    add     rdx, 4
    dec     rcx
    jnz     .residuals

.done:
    ret

; -----------------------------------------------------------------------------
; umath_clamp_i32_count_clamped - count how many elements in signed 32-bit array fall outside range
; args:    rdi = source pointer (src)
;          rsi = size of array (count)
;          edx = minimum boundary (min_val)
;          ecx = maximum boundary (max_val)
; returns: rax = count of elements clamped
; -----------------------------------------------------------------------------
global umath_clamp_i32_count_clamped
umath_clamp_i32_count_clamped:
    xor     rax, rax            ; count = 0
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done

    movd    xmm14, edx
    pshufd  xmm14, xmm14, 0     ; xmm14 = min_val
    movd    xmm15, ecx
    pshufd  xmm15, xmm15, 0     ; xmm15 = max_val

    cmp     rsi, 16
    jb      .single_ints

    mov     rcx, rsi
    shr     rcx, 4

.loop_unrolled:
    movups  xmm0, [rdi]
    movups  xmm1, [rdi + 16]
    movups  xmm2, [rdi + 32]
    movups  xmm3, [rdi + 48]

    ; Check val < min_val => pcmpgtd min_val, val
    movups  xmm4, xmm14
    movups  xmm5, xmm14
    movups  xmm6, xmm14
    movups  xmm7, xmm14

    pcmpgtd xmm4, xmm0
    pcmpgtd xmm5, xmm1
    pcmpgtd xmm6, xmm2
    pcmpgtd xmm7, xmm3

    ; Check val > max_val => pcmpgtd val, max_val
    movups  xmm8, xmm0
    movups  xmm9, xmm1
    movups  xmm10, xmm2
    movups  xmm11, xmm3

    pcmpgtd xmm8, xmm15
    pcmpgtd xmm9, xmm15
    pcmpgtd xmm10, xmm15
    pcmpgtd xmm11, xmm15

    ; Combine masks
    por     xmm4, xmm8
    por     xmm5, xmm9
    por     xmm6, xmm10
    por     xmm7, xmm11

    ; Extract signs to count popcnt
    movmskps r8d, xmm4
    popcnt  r8d, r8d
    add     rax, r8

    movmskps r8d, xmm5
    popcnt  r8d, r8d
    add     rax, r8

    movmskps r8d, xmm6
    popcnt  r8d, r8d
    add     rax, r8

    movmskps r8d, xmm7
    popcnt  r8d, r8d
    add     rax, r8

    add     rdi, 64
    dec     rcx
    jnz     .loop_unrolled

    and     rsi, 15
    jz      .done

.single_ints:
    cmp     rsi, 4
    jb      .residuals

    mov     rcx, rsi
    shr     rcx, 2

.loop_vector:
    movups  xmm0, [rdi]
    movups  xmm1, xmm14
    movups  xmm2, xmm0

    pcmpgtd xmm1, xmm0          ; min > val
    pcmpgtd xmm2, xmm15          ; val > max
    por     xmm1, xmm2

    movmskps r8d, xmm1
    popcnt  r8d, r8d
    add     rax, r8

    add     rdi, 16
    dec     rcx
    jnz     .loop_vector

    and     rsi, 3
    jz      .done

.residuals:
    mov     r8d, [rdi]
    cmp     r8d, edx
    jl      .is_clamped
    cmp     r8d, ecx
    jg      .is_clamped
    jmp     .next_residual

.is_clamped:
    inc     rax

.next_residual:
    add     rdi, 4
    dec     rsi
    jnz     .residuals

.done:
    ret

%endif ; GUARD_LIB_UMATH_SCALAR_CLAMP_I32_ASM
