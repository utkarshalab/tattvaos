%ifndef GUARD_LIB_UMATH_SCALAR_MAX_I32_ASM
%define GUARD_LIB_UMATH_SCALAR_MAX_I32_ASM
; =============================================================================
; umath - unified math library
; scalar/max_i32.asm - signed 32-bit integer maximum implementations
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; Performance Optimizations:
;   - Vectorized element-wise maximums unrolled 4x (using SSE4.1 pmaxsd).
;   - Vectorized reductions with log-step horizontal max.
;   - Argument reduction (argmax index tracking) with branchless checks.
;   - Inplace clamping/clipping for activation functions (e.g. ReLU-like).
;   - Filter copying of elements exceeding thresholds.
; =============================================================================

bits 64
section .text

; -----------------------------------------------------------------------------
; umath_max_i32 - scalar signed 32-bit integer maximum
; args:    edi = input value a
;          esi = input value b
; returns: eax = max(a, b)
; -----------------------------------------------------------------------------
global umath_max_i32
umath_max_i32:
    mov     eax, edi            ; eax = a
    cmp     edi, esi            ; compare a and b
    cmovl   eax, esi            ; if a < b, eax = b
    ret

; -----------------------------------------------------------------------------
; umath_max_i32_array - compute element-wise maximum of two signed 32-bit integer arrays
; args:    rdi = destination pointer (dst)
;          rsi = source pointer a (src_a)
;          rdx = source pointer b (src_b)
;          rcx = size of arrays (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_max_i32_array
umath_max_i32_array:
    ; Null pointer check and zero count guard
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done
    test    rdx, rdx
    jz      .done
    test    rcx, rcx
    jz      .done

    ; If size < 16, skip unrolled vectorized loop
    cmp     rcx, 16
    jb      .single_ints

    mov     r8, rcx
    shr     r8, 4               ; count of 16-int blocks

.loop_unrolled:
    ; Load 16 elements from src_a (4 xmm registers)
    movups  xmm0, [rsi]
    movups  xmm1, [rsi + 16]
    movups  xmm2, [rsi + 32]
    movups  xmm3, [rsi + 48]

    ; Load 16 elements from src_b (4 xmm registers)
    movups  xmm4, [rdx]
    movups  xmm5, [rdx + 16]
    movups  xmm6, [rdx + 32]
    movups  xmm7, [rdx + 48]

    ; Compute element-wise signed 32-bit maximums (SSE4.1 pmaxsd)
    pmaxsd  xmm0, xmm4
    pmaxsd  xmm1, xmm5
    pmaxsd  xmm2, xmm6
    pmaxsd  xmm3, xmm7

    ; Store results to dst
    movups  [rdi], xmm0
    movups  [rdi + 16], xmm1
    movups  [rdi + 32], xmm2
    movups  [rdi + 48], xmm3

    add     rsi, 64
    add     rdx, 64
    add     rdi, 64
    dec     r8
    jnz     .loop_unrolled

    and     rcx, 15
    jz      .done

.single_ints:
    cmp     rcx, 4
    jb      .residuals

    mov     r8, rcx
    shr     r8, 2               ; count of 4-int blocks

.loop_vector:
    movups  xmm0, [rsi]
    movups  xmm1, [rdx]
    pmaxsd  xmm0, xmm1
    movups  [rdi], xmm0
    add     rsi, 16
    add     rdx, 16
    add     rdi, 16
    dec     r8
    jnz     .loop_vector

    and     rcx, 3
    jz      .done

.residuals:
    mov     eax, [rsi]
    mov     r8d, [rdx]
    cmp     eax, r8d
    cmovl   eax, r8d
    mov     [rdi], eax
    add     rsi, 4
    add     rdx, 4
    add     rdi, 4
    dec     rcx
    jnz     .residuals

.done:
    ret

; -----------------------------------------------------------------------------
; umath_max_i32_array_inplace - compute in-place element-wise maximum of two arrays
; args:    rdi = destination/source_a pointer (dst_src)
;          rsi = source pointer b (src_b)
;          rdx = size of arrays (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_max_i32_array_inplace
umath_max_i32_array_inplace:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done
    test    rdx, rdx
    jz      .done

    cmp     rdx, 16
    jb      .single_ints

    mov     rcx, rdx
    shr     rcx, 4

.loop_unrolled:
    movups  xmm0, [rdi]
    movups  xmm1, [rdi + 16]
    movups  xmm2, [rdi + 32]
    movups  xmm3, [rdi + 48]

    movups  xmm4, [rsi]
    movups  xmm5, [rsi + 16]
    movups  xmm6, [rsi + 32]
    movups  xmm7, [rsi + 48]

    pmaxsd  xmm0, xmm4
    pmaxsd  xmm1, xmm5
    pmaxsd  xmm2, xmm6
    pmaxsd  xmm3, xmm7

    movups  [rdi], xmm0
    movups  [rdi + 16], xmm1
    movups  [rdi + 32], xmm2
    movups  [rdi + 48], xmm3

    add     rdi, 64
    add     rsi, 64
    dec     rcx
    jnz     .loop_unrolled

    and     rdx, 15
    jz      .done

.single_ints:
    cmp     rdx, 4
    jb      .residuals

    mov     rcx, rdx
    shr     rcx, 2

.loop_vector:
    movups  xmm0, [rdi]
    movups  xmm1, [rsi]
    pmaxsd  xmm0, xmm1
    movups  [rdi], xmm0
    add     rdi, 16
    add     rsi, 16
    dec     rcx
    jnz     .loop_vector

    and     rdx, 3
    jz      .done

.residuals:
    mov     eax, [rdi]
    mov     r8d, [rsi]
    cmp     eax, r8d
    cmovl   eax, r8d
    mov     [rdi], eax
    add     rdi, 4
    add     rsi, 4
    dec     rdx
    jnz     .residuals

.done:
    ret

; -----------------------------------------------------------------------------
; umath_max_i32_reduce - reduce an array of signed 32-bit integers to its maximum value
; args:    rdi = source pointer (src)
;          rsi = size of array (count)
; returns: eax = maximum value in array, or 0 if empty
; -----------------------------------------------------------------------------
global umath_max_i32_reduce
umath_max_i32_reduce:
    xor     eax, eax
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done

    ; If we have >= 16 elements, we can do a vectorized reduction
    cmp     rsi, 16
    jb      .scalar_reduce

    ; Initialize 4-element maximum vector with the first 4 elements
    movups  xmm0, [rdi]
    add     rdi, 16
    mov     rcx, rsi
    sub     rcx, 4              ; remaining elements to process
    shr     rcx, 2              ; count of 4-element vectors

.loop_vector:
    movups  xmm1, [rdi]
    pmaxsd  xmm0, xmm1
    add     rdi, 16
    dec     rcx
    jnz     .loop_vector

    ; Reduce xmm0 = [v3, v2, v1, v0] horizontally to single scalar in low slot
    pshufd  xmm1, xmm0, 0x0E    ; xmm1 = [v3, v2, v3, v2]
    pmaxsd  xmm0, xmm1          ; xmm0 = [max(v3,v3), max(v2,v2), max(v1,v3), max(v0,v2)]
    pshufd  xmm1, xmm0, 0x01    ; shuffle low slots
    pmaxsd  xmm0, xmm1          ; horizontal max of low slot and high slot
    movd    eax, xmm0           ; extract result

    and     rsi, 3
    jz      .done

.loop_residuals:
    mov     edx, [rdi]
    cmp     eax, edx
    cmovl   eax, edx
    add     rdi, 4
    dec     rsi
    jnz     .loop_residuals
    ret

.scalar_reduce:
    mov     eax, [rdi]
    add     rdi, 4
    dec     rsi
    jz      .done

.loop_scalar:
    mov     edx, [rdi]
    cmp     eax, edx
    cmovl   eax, edx
    add     rdi, 4
    dec     rsi
    jnz     .loop_scalar

.done:
    ret

; -----------------------------------------------------------------------------
; umath_max_i32_reduce_index - reduce array of signed 32-bit integers to index of maximum (argmax)
; args:    rdi = source pointer (src)
;          rsi = size of array (count)
; returns: rax = index of first occurrence of the maximum value, or -1 if empty
; -----------------------------------------------------------------------------
global umath_max_i32_reduce_index
umath_max_i32_reduce_index:
    mov     rax, -1
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done

    xor     rax, rax            ; max_index = 0
    mov     r8d, [rdi]          ; max_val = src[0]
    
    mov     rcx, 1              ; current_index = 1
    dec     rsi                 ; count--
    jz      .done

.loop_reduce:
    mov     r9d, [rdi + rcx * 4]
    
    cmp     r9d, r8d
    jle     .next_item          ; if current_val <= max_val, skip

    ; Update maximum and its index
    mov     r8d, r9d
    mov     rax, rcx

.next_item:
    inc     rcx
    dec     rsi
    jnz     .loop_reduce

.done:
    ret

; -----------------------------------------------------------------------------
; umath_max_i32_inplace_clip - clips elements in-place to not fall below threshold
;                              val = max(val, threshold)
; args:    rdi = buffer pointer (buf)
;          rsi = size of array (count)
;          edx = threshold value
; returns: void
; -----------------------------------------------------------------------------
global umath_max_i32_inplace_clip
umath_max_i32_inplace_clip:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done

    ; Broadcast threshold across all 4 slots of XMM15
    movd    xmm15, edx
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

    pmaxsd  xmm0, xmm15
    pmaxsd  xmm1, xmm15
    pmaxsd  xmm2, xmm15
    pmaxsd  xmm3, xmm15

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
    pmaxsd  xmm0, xmm15
    movups  [rdi], xmm0
    add     rdi, 16
    dec     rcx
    jnz     .loop_vector

    and     rsi, 3
    jz      .done

.residuals:
    mov     eax, [rdi]
    cmp     eax, edx
    cmovl   eax, edx
    mov     [rdi], eax
    add     rdi, 4
    dec     rsi
    jnz     .residuals

.done:
    ret

; -----------------------------------------------------------------------------
; umath_max_i32_reduce_range - reduce sub-segment of array to its maximum value
; args:    rdi = source pointer (src)
;          rsi = start index
;          rdx = end index (exclusive)
; returns: eax = maximum value in range, or 0 if invalid
; -----------------------------------------------------------------------------
global umath_max_i32_reduce_range
umath_max_i32_reduce_range:
    xor     eax, eax
    test    rdi, rdi
    jz      .done
    cmp     rsi, rdx
    jae     .done               ; invalid range

    ; count = end - start
    mov     rcx, rdx
    sub     rcx, rsi

    ; offset pointer: src + start * 4
    lea     rdi, [rdi + rsi * 4]

    mov     eax, [rdi]
    add     rdi, 4
    dec     rcx
    jz      .done

.loop_reduce:
    mov     edx, [rdi]
    cmp     eax, edx
    cmovl   eax, edx
    add     rdi, 4
    dec     rcx
    jnz     .loop_reduce

.done:
    ret

; -----------------------------------------------------------------------------
; umath_max_i32_filter - filter elements exceeding a threshold into a dest array
; args:    rdi = destination pointer (dst)
;          rsi = source pointer (src)
;          rdx = size of source array (count)
;          ecx = threshold value
; returns: rax = count of copied elements
; -----------------------------------------------------------------------------
global umath_max_i32_filter
umath_max_i32_filter:
    xor     rax, rax            ; written count = 0
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done
    test    rdx, rdx
    jz      .done

.loop_filter:
    mov     r8d, [rsi]          ; current element
    cmp     r8d, ecx            ; check if greater than threshold
    jle     .skip

    mov     [rdi + rax * 4], r8d ; copy to destination
    inc     rax

.skip:
    add     rsi, 4
    dec     rdx
    jnz     .loop_filter

.done:
    ret

%endif ; GUARD_LIB_UMATH_SCALAR_MAX_I32_ASM
