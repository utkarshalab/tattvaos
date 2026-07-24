; =============================================================================
; umath - unified math library
; scalar/max_i64.asm - signed 64-bit integer maximum implementations
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; Performance Optimizations:
;   - Vectorized element-wise maximums unrolled 4x (using SSE4.1 pcmpgtq and blending).
;   - Vectorized reductions with horizontal log-step extraction.
;   - Argument reduction (argmax index tracking) with branchless checks.
;   - Inplace clamping/clipping for activation functions (e.g. ReLU-like).
;   - Filter copying of elements exceeding thresholds.
; =============================================================================

bits 64
section .text

; -----------------------------------------------------------------------------
; umath_max_i64 - scalar signed 64-bit integer maximum
; args:    rdi = input value a
;          rsi = input value b
; returns: rax = max(a, b)
; -----------------------------------------------------------------------------
global umath_max_i64
umath_max_i64:
    mov     rax, rdi            ; rax = a
    cmp     rdi, rsi            ; compare a and b
    cmovl   rax, rsi            ; if a < b, rax = b
    ret

; -----------------------------------------------------------------------------
; umath_max_i64_array - compute element-wise maximum of two signed 64-bit integer arrays
; args:    rdi = destination pointer (dst)
;          rsi = source pointer a (src_a)
;          rdx = source pointer b (src_b)
;          rcx = size of arrays (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_max_i64_array
umath_max_i64_array:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done
    test    rdx, rdx
    jz      .done
    test    rcx, rcx
    jz      .done

    ; If size < 8, skip unrolled vectorized loop (8 elements of 8 bytes = 64 bytes)
    cmp     rcx, 8
    jb      .single_ints

    mov     r8, rcx
    shr     r8, 3               ; count of 8-int blocks (64 bytes each)

.loop_unrolled:
    ; Load 8 elements from src_a (4 xmm registers, 2 QWORDs each)
    movups  xmm0, [rsi]
    movups  xmm1, [rsi + 16]
    movups  xmm2, [rsi + 32]
    movups  xmm3, [rsi + 48]

    ; Load 8 elements from src_b
    movups  xmm4, [rdx]
    movups  xmm5, [rdx + 16]
    movups  xmm6, [rdx + 32]
    movups  xmm7, [rdx + 48]

    ; Compare and blend for xmm0 and xmm4
    movups  xmm8, xmm0          ; xmm8 = a
    pcmpgtq xmm8, xmm4          ; xmm8 = mask (a > b)
    pand    xmm0, xmm8          ; xmm0 = a & mask
    pandn   xmm8, xmm4          ; xmm8 = ~mask & b
    por     xmm0, xmm8          ; xmm0 = max(a, b)

    ; Compare and blend for xmm1 and xmm5
    movups  xmm9, xmm1
    pcmpgtq xmm9, xmm5
    pand    xmm1, xmm9
    pandn   xmm9, xmm5
    por     xmm1, xmm9

    ; Compare and blend for xmm2 and xmm6
    movups  xmm10, xmm2
    pcmpgtq xmm10, xmm6
    pand    xmm2, xmm10
    pandn   xmm10, xmm6
    por     xmm2, xmm10

    ; Compare and blend for xmm3 and xmm7
    movups  xmm11, xmm3
    pcmpgtq xmm11, xmm7
    pand    xmm3, xmm11
    pandn   xmm11, xmm7
    por     xmm3, xmm11

    ; Store results
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

.single_ints:
    cmp     rcx, 2
    jb      .residuals

    mov     r8, rcx
    shr     r8, 1               ; count of 2-int vectors

.loop_vector:
    movups  xmm0, [rsi]
    movups  xmm1, [rdx]
    
    movups  xmm2, xmm0
    pcmpgtq xmm2, xmm1
    pand    xmm0, xmm2
    pandn   xmm2, xmm1
    por     xmm0, xmm2

    movups  [rdi], xmm0
    add     rsi, 16
    add     rdx, 16
    add     rdi, 16
    dec     r8
    jnz     .loop_vector

    and     rcx, 1
    jz      .done

.residuals:
    mov     rax, [rsi]
    mov     r8, [rdx]
    cmp     rax, r8
    cmovl   rax, r8
    mov     [rdi], rax
    add     rsi, 8
    add     rdx, 8
    add     rdi, 8
    dec     rcx
    jnz     .residuals

.done:
    ret

; -----------------------------------------------------------------------------
; umath_max_i64_array_inplace - compute in-place element-wise maximum of two arrays
; args:    rdi = destination/source_a pointer (dst_src)
;          rsi = source pointer b (src_b)
;          rdx = size of arrays (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_max_i64_array_inplace
umath_max_i64_array_inplace:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done
    test    rdx, rdx
    jz      .done

    cmp     rdx, 8
    jb      .single_ints

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

    movups  xmm8, xmm0
    pcmpgtq xmm8, xmm4
    pand    xmm0, xmm8
    pandn   xmm8, xmm4
    por     xmm0, xmm8

    movups  xmm9, xmm1
    pcmpgtq xmm9, xmm5
    pand    xmm1, xmm9
    pandn   xmm9, xmm5
    por     xmm1, xmm9

    movups  xmm10, xmm2
    pcmpgtq xmm10, xmm6
    pand    xmm2, xmm10
    pandn   xmm10, xmm6
    por     xmm2, xmm10

    movups  xmm11, xmm3
    pcmpgtq xmm11, xmm7
    pand    xmm3, xmm11
    pandn   xmm11, xmm7
    por     xmm3, xmm11

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

.single_ints:
    cmp     rdx, 2
    jb      .residuals

    mov     rcx, rdx
    shr     rcx, 1

.loop_vector:
    movups  xmm0, [rdi]
    movups  xmm1, [rsi]

    movups  xmm2, xmm0
    pcmpgtq xmm2, xmm1
    pand    xmm0, xmm2
    pandn   xmm2, xmm1
    por     xmm0, xmm2

    movups  [rdi], xmm0
    add     rdi, 16
    add     rsi, 16
    dec     rcx
    jnz     .loop_vector

    and     rdx, 1
    jz      .done

.residuals:
    mov     rax, [rdi]
    mov     r8, [rsi]
    cmp     rax, r8
    cmovl   rax, r8
    mov     [rdi], rax
    add     rdi, 8
    add     rsi, 8
    dec     rdx
    jnz     .residuals

.done:
    ret

; -----------------------------------------------------------------------------
; umath_max_i64_reduce - reduce an array of signed 64-bit integers to its maximum value
; args:    rdi = source pointer (src)
;          rsi = size of array (count)
; returns: rax = maximum value in array, or 0 if empty
; -----------------------------------------------------------------------------
global umath_max_i64_reduce
umath_max_i64_reduce:
    xor     rax, rax
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done

    cmp     rsi, 8
    jb      .scalar_reduce

    ; Initialize accumulator xmm0 with the first 2 elements
    movups  xmm0, [rdi]
    add     rdi, 16
    mov     rcx, rsi
    sub     rcx, 2
    shr     rcx, 1              ; count of 2-element vectors

.loop_vector:
    movups  xmm1, [rdi]
    
    movups  xmm2, xmm0
    pcmpgtq xmm2, xmm1
    pand    xmm0, xmm2
    pandn   xmm2, xmm1
    por     xmm0, xmm2

    add     rdi, 16
    dec     rcx
    jnz     .loop_vector

    ; Horizontal max of the two lanes in xmm0
    movhlps xmm1, xmm0          ; xmm1 = [0, max_high]
    movq    rax, xmm0           ; rax = max_low
    movq    rdx, xmm1           ; rdx = max_high
    cmp     rax, rdx
    cmovl   rax, rdx

    and     rsi, 1
    jz      .done

    ; Residual handling (at most 1 element remains)
    mov     rdx, [rdi]
    cmp     rax, rdx
    cmovl   rax, rdx
    ret

.scalar_reduce:
    mov     rax, [rdi]
    add     rdi, 8
    dec     rsi
    jz      .done

.loop_scalar:
    mov     rdx, [rdi]
    cmp     rax, rdx
    cmovl   rax, rdx
    add     rdi, 8
    dec     rsi
    jnz     .loop_scalar

.done:
    ret

; -----------------------------------------------------------------------------
; umath_max_i64_reduce_index - reduce array of signed 64-bit integers to index of maximum (argmax)
; args:    rdi = source pointer (src)
;          rsi = size of array (count)
; returns: rax = index of first occurrence of the maximum value, or -1 if empty
; -----------------------------------------------------------------------------
global umath_max_i64_reduce_index
umath_max_i64_reduce_index:
    mov     rax, -1
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done

    xor     rax, rax            ; max_index = 0
    mov     r8, [rdi]           ; max_val = src[0]
    
    mov     rcx, 1              ; current_index = 1
    dec     rsi                 ; count--
    jz      .done

.loop_reduce:
    mov     r9, [rdi + rcx * 8]
    
    cmp     r9, r8
    jle     .next_item

    ; Update maximum and its index
    mov     r8, r9
    mov     rax, rcx

.next_item:
    inc     rcx
    dec     rsi
    jnz     .loop_reduce

.done:
    ret

; -----------------------------------------------------------------------------
; umath_max_i64_inplace_clip - clips elements in-place to not fall below threshold
;                              val = max(val, threshold)
; args:    rdi = buffer pointer (buf)
;          rsi = size of array (count)
;          rdx = threshold value
; returns: void
; -----------------------------------------------------------------------------
global umath_max_i64_inplace_clip
umath_max_i64_inplace_clip:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done

    ; Broadcast threshold across both 64-bit lanes of XMM15
    movq    xmm15, rdx
    punpcklqdq xmm15, xmm15

    cmp     rsi, 8
    jb      .single_ints

    mov     rcx, rsi
    shr     rcx, 3

.loop_unrolled:
    movups  xmm0, [rdi]
    movups  xmm1, [rdi + 16]
    movups  xmm2, [rdi + 32]
    movups  xmm3, [rdi + 48]

    ; Apply max(xmm0, xmm15)
    movups  xmm8, xmm0
    pcmpgtq xmm8, xmm15
    pand    xmm0, xmm8
    pandn   xmm8, xmm15
    por     xmm0, xmm8

    ; Apply max(xmm1, xmm15)
    movups  xmm9, xmm1
    pcmpgtq xmm9, xmm15
    pand    xmm1, xmm9
    pandn   xmm9, xmm15
    por     xmm1, xmm9

    ; Apply max(xmm2, xmm15)
    movups  xmm10, xmm2
    pcmpgtq xmm10, xmm15
    pand    xmm2, xmm10
    pandn   xmm10, xmm15
    por     xmm2, xmm10

    ; Apply max(xmm3, xmm15)
    movups  xmm11, xmm3
    pcmpgtq xmm11, xmm15
    pand    xmm3, xmm11
    pandn   xmm11, xmm15
    por     xmm3, xmm11

    ; Store results
    movups  [rdi], xmm0
    movups  [rdi + 16], xmm1
    movups  [rdi + 32], xmm2
    movups  [rdi + 48], xmm3

    add     rdi, 64
    dec     rcx
    jnz     .loop_unrolled

    and     rsi, 7
    jz      .done

.single_ints:
    cmp     rsi, 2
    jb      .residuals

    mov     rcx, rsi
    shr     rcx, 1

.loop_vector:
    movups  xmm0, [rdi]
    
    movups  xmm1, xmm0
    pcmpgtq xmm1, xmm15
    pand    xmm0, xmm1
    pandn   xmm1, xmm15
    por     xmm0, xmm1

    movups  [rdi], xmm0
    add     rdi, 16
    dec     rcx
    jnz     .loop_vector

    and     rsi, 1
    jz      .done

.residuals:
    mov     rax, [rdi]
    cmp     rax, rdx
    cmovl   rax, rdx
    mov     [rdi], rax
    add     rdi, 8
    dec     rsi
    jnz     .residuals

.done:
    ret

; -----------------------------------------------------------------------------
; umath_max_i64_reduce_range - reduce sub-segment of array to its maximum value
; args:    rdi = source pointer (src)
;          rsi = start index
;          rdx = end index (exclusive)
; returns: rax = maximum value in range, or 0 if invalid
; -----------------------------------------------------------------------------
global umath_max_i64_reduce_range
umath_max_i64_reduce_range:
    xor     rax, rax
    test    rdi, rdi
    jz      .done
    cmp     rsi, rdx
    jae     .done               ; invalid range

    ; count = end - start
    mov     rcx, rdx
    sub     rcx, rsi

    ; offset pointer: src + start * 8
    lea     rdi, [rdi + rsi * 8]

    mov     rax, [rdi]
    add     rdi, 8
    dec     rcx
    jz      .done

.loop_reduce:
    mov     rdx, [rdi]
    cmp     rax, rdx
    cmovl   rax, rdx
    add     rdi, 8
    dec     rcx
    jnz     .loop_reduce

.done:
    ret

; -----------------------------------------------------------------------------
; umath_max_i64_filter - filter elements exceeding a threshold into a dest array
; args:    rdi = destination pointer (dst)
;          rsi = source pointer (src)
;          rdx = size of source array (count)
;          rcx = threshold value
; returns: rax = count of copied elements
; -----------------------------------------------------------------------------
global umath_max_i64_filter
umath_max_i64_filter:
    xor     rax, rax            ; written count = 0
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done
    test    rdx, rdx
    jz      .done

.loop_filter:
    mov     r8, [rsi]           ; current element
    cmp     r8, rcx             ; check if greater than threshold
    jle     .skip

    mov     [rdi + rax * 8], r8 ; copy to destination
    inc     rax

.skip:
    add     rsi, 8
    dec     rdx
    jnz     .loop_filter

.done:
    ret
