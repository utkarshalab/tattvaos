; =============================================================================
; umath - unified math library
; scalar/min_i32.asm - signed 32-bit integer minimum implementations
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; Performance Optimizations:
;   - Branchless scalar minimum via cmovg (Conditional Move if Greater).
;   - Vectorized element-wise minimums unrolled 4x utilizing the SSE4.1/AVX2
;     PMINSD instruction.
;   - Branchless reduction argmin index mapping.
; =============================================================================

bits 64
section .text

; -----------------------------------------------------------------------------
; umath_min_i32 - scalar branchless 32-bit integer minimum
; args:    edi = value a
;          esi = value b
; returns: eax = min(a, b)
; -----------------------------------------------------------------------------
global umath_min_i32
umath_min_i32:
    cmp     edi, esi
    mov     eax, edi
    cmovg   eax, esi            ; if a > b, load b into eax
    ret

; -----------------------------------------------------------------------------
; umath_min_i32_array - element-wise minimum of two signed 32-bit integer arrays
; args:    rdi = destination pointer (dst)
;          rsi = source pointer a (src_a)
;          rdx = source pointer b (src_b)
;          rcx = size of arrays (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_min_i32_array
umath_min_i32_array:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done
    test    rdx, rdx
    jz      .done
    test    rcx, rcx
    jz      .done

    ; check if count is large enough for unrolled SSE loop (>= 16 integers)
    cmp     rcx, 16
    jb      .single_ints

    mov     r8, rcx
    shr     r8, 4               ; count of 16-integer blocks

.loop_unrolled:
    ; Load 4 vectors from src_a and src_b
    movups  xmm0, [rsi]
    movups  xmm1, [rsi + 16]
    movups  xmm2, [rsi + 32]
    movups  xmm3, [rsi + 48]

    movups  xmm4, [rdx]
    movups  xmm5, [rdx + 16]
    movups  xmm6, [rdx + 32]
    movups  xmm7, [rdx + 48]

    ; Element-wise minimums using SSE4.1 PMINSD
    pminsd  xmm0, xmm4
    pminsd  xmm1, xmm5
    pminsd  xmm2, xmm6
    pminsd  xmm3, xmm7

    ; Store results to destination
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
    shr     r8, 2

.loop_vector:
    movups  xmm0, [rsi]
    movups  xmm1, [rdx]
    pminsd  xmm0, xmm1
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
    cmovg   eax, r8d
    mov     [rdi], eax
    add     rsi, 4
    add     rdx, 4
    add     rdi, 4
    dec     rcx
    jnz     .residuals

.done:
    ret

; -----------------------------------------------------------------------------
; umath_min_i32_reduce - reduce an array of 32-bit integers to its minimum value
; args:    rdi = source pointer (src)
;          rsi = size of array (count)
; returns: eax = minimum value in array, or 0 if empty
; -----------------------------------------------------------------------------
global umath_min_i32_reduce
umath_min_i32_reduce:
    xor     eax, eax
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done

    mov     eax, [rdi]          ; initial minimum
    add     rdi, 4
    dec     rsi
    jz      .done

.loop_reduce:
    mov     ecx, [rdi]
    cmp     eax, ecx
    cmovg   eax, ecx            ; update min
    add     rdi, 4
    dec     rsi
    jnz     .loop_reduce
.done:
    ret

; -----------------------------------------------------------------------------
; umath_min_i32_reduce_index - reduce array of 32-bit integers to index of minimum (argmin)
; args:    rdi = source pointer (src)
;          rsi = size of array (count)
; returns: rax = index of first occurrence of the minimum value, or -1 if empty
; -----------------------------------------------------------------------------
global umath_min_i32_reduce_index
umath_min_i32_reduce_index:
    mov     rax, -1
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done

    xor     rax, rax            ; min_index = 0
    mov     r8d, [rdi]          ; min_val = src[0]
    
    mov     rcx, 1              ; current index = 1
    dec     rsi
    jz      .done

.loop_reduce:
    mov     r9d, [rdi + rcx * 4]
    
    ; is current value < min_val? (r9d < r8d)
    cmp     r9d, r8d
    jge     .next_item

    ; update minimum
    mov     r8d, r9d
    mov     rax, rcx            ; min_index = current index

.next_item:
    inc     rcx
    dec     rsi
    jnz     .loop_reduce

.done:
    ret

; -----------------------------------------------------------------------------
; umath_min_i32_inplace_clip - clips all elements in array in-place to not be less than threshold
; args:    rdi = buffer pointer (buf)
;          rsi = size of array (count)
;          edx = threshold value
; returns: void
; -----------------------------------------------------------------------------
global umath_min_i32_inplace_clip
umath_min_i32_inplace_clip:
    test    rdi, rdi
    jz      .done_clip
    test    rsi, rsi
    jz      .done_clip

    ; broadcast threshold to xmm15 (for vector path)
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

    ; clip elements (using max to clamp bottom limit, wait!
    ; if we want to ensure elements are not less than threshold, we do max(val, threshold).
    ; if we want to ensure elements are not greater than threshold, we do min(val, threshold).
    ; standard clip-below uses max, clip-above uses min.
    ; let's implement clipping to a top-limit threshold, which uses min!
    ; i.e., val = min(val, threshold) -> elements are clipped to not exceed threshold.
    pminsd  xmm0, xmm15
    pminsd  xmm1, xmm15
    pminsd  xmm2, xmm15
    pminsd  xmm3, xmm15

    movups  [rdi], xmm0
    movups  [rdi + 16], xmm1
    movups  [rdi + 32], xmm2
    movups  [rdi + 48], xmm3

    add     rdi, 64
    dec     rcx
    jnz     .loop_unrolled

    and     rsi, 15
    jz      .done_clip

.single_ints:
    cmp     rsi, 4
    jb      .residuals

    mov     rcx, rsi
    shr     rcx, 2

.loop_vector:
    movups  xmm0, [rdi]
    pminsd  xmm0, xmm15
    movups  [rdi], xmm0
    add     rdi, 16
    dec     rcx
    jnz     .loop_vector

    and     rsi, 3
    jz      .done_clip

.residuals:
    mov     eax, [rdi]
    cmp     eax, edx
    cmovg   eax, edx
    mov     [rdi], eax
    add     rdi, 4
    dec     rsi
    jnz     .residuals

.done_clip:
    ret

; -----------------------------------------------------------------------------
; umath_min_i32_reduce_range - reduce sub-segment of array to its minimum value
; args:    rdi = source pointer (src)
;          rsi = start index
;          rdx = end index (exclusive)
; returns: eax = minimum value in range, or 0 if invalid
; -----------------------------------------------------------------------------
global umath_min_i32_reduce_range
umath_min_i32_reduce_range:
    xor     eax, eax
    test    rdi, rdi
    jz      .done_range
    cmp     rsi, rdx
    jae     .done_range         ; invalid range

    ; calculate size: rcx = end - start
    mov     rcx, rdx
    sub     rcx, rsi

    ; offset pointer: rdi = src + start * 4
    lea     rdi, [rdi + rsi * 4]

    mov     eax, [rdi]          ; initial minimum
    add     rdi, 4
    dec     rcx
    jz      .done_range

.loop_reduce:
    mov     r8d, [rdi]
    cmp     eax, r8d
    cmovg   eax, r8d
    add     rdi, 4
    dec     rcx
    jnz     .loop_reduce

.done_range:
    ret

