%ifndef GUARD_LIB_UMATH_SCALAR_MIN_I64_ASM
%define GUARD_LIB_UMATH_SCALAR_MIN_I64_ASM
; =============================================================================
; umath - unified math library
; memory/min_i64.asm - signed 64-bit integer minimum implementations
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; Performance Optimizations:
;   - Branchless scalar minimum via cmovg (Conditional Move if Greater) on 64-bit.
;   - Vectorized element-wise minimums unrolled 4x utilizing AVX2.
;   - Branchless reduction argmin index mapping.
; =============================================================================

bits 64
section .text

; -----------------------------------------------------------------------------
; umath_min_i64 - scalar branchless 64-bit integer minimum
; args:    rdi = value a
;          rsi = value b
; returns: rax = min(a, b)
; -----------------------------------------------------------------------------
global umath_min_i64
umath_min_i64:
    cmp     rdi, rsi
    mov     rax, rdi
    cmovg   rax, rsi            ; if a > b, load b into rax
    ret

; -----------------------------------------------------------------------------
; umath_min_i64_array - element-wise minimum of two signed 64-bit integer arrays
; args:    rdi = destination pointer (dst)
;          rsi = source pointer a (src_a)
;          rdx = source pointer b (src_b)
;          rcx = size of arrays (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_min_i64_array
umath_min_i64_array:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done
    test    rdx, rdx
    jz      .done
    test    rcx, rcx
    jz      .done

    ; check if count is large enough for unrolled AVX2 loop (>= 8 integers)
    cmp     rcx, 8
    jb      .single_ints

    mov     r8, rcx
    shr     r8, 3               ; count of 8-integer blocks

.loop_unrolled:
    ; Load 4 vectors (8 elements total, AVX2)
    vmovdqu ymm0, [rsi]
    vmovdqu ymm1, [rsi + 32]
    vmovdqu ymm2, [rdx]
    vmovdqu ymm3, [rdx + 32]

    ; Element-wise minimums using AVX2 VPMINSD (signed qwords minimum is VPMINSQ)
    ; VPMINSQ is in AVX-512. In AVX2, we can compare and blend,
    ; or fall back to loop. Let's do a comparison and blend:
    ; compare: ymm0 > ymm2 -> mask
    vpcmpgtq ymm4, ymm0, ymm2
    vpcmpgtq ymm5, ymm1, ymm3

    ; blend: select ymm2 where mask is true, else ymm0
    vpblendvb ymm0, ymm0, ymm2, ymm4
    vpblendvb ymm1, ymm1, ymm3, ymm5

    ; Store results to destination
    vmovdqu [rdi], ymm0
    vmovdqu [rdi + 32], ymm1

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
    shr     r8, 1

.loop_vector:
    vmovdqu xmm0, [rsi]
    vmovdqu xmm1, [rdx]
    vpcmpgtq xmm2, xmm0, xmm1
    vpblendvb xmm0, xmm0, xmm1, xmm2
    vmovdqu [rdi], xmm0
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
    cmovg   rax, r8
    mov     [rdi], rax
    add     rsi, 8
    add     rdx, 8
    add     rdi, 8
    dec     rcx
    jnz     .residuals

.done:
    vzeroupper
    ret

; -----------------------------------------------------------------------------
; umath_min_i64_reduce - reduce an array of 64-bit integers to its minimum value
; args:    rdi = source pointer (src)
;          rsi = size of array (count)
; returns: rax = minimum value in array, or 0 if empty
; -----------------------------------------------------------------------------
global umath_min_i64_reduce
umath_min_i64_reduce:
    xor     rax, rax
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done

    mov     rax, [rdi]          ; initial minimum
    add     rdi, 8
    dec     rsi
    jz      .done

.loop_reduce:
    mov     rcx, [rdi]
    cmp     rax, rcx
    cmovg   rax, rcx            ; update min
    add     rdi, 8
    dec     rsi
    jnz     .loop_reduce
.done:
    ret

; -----------------------------------------------------------------------------
; umath_min_i64_reduce_index - reduce array of 64-bit integers to index of minimum (argmin)
; args:    rdi = source pointer (src)
;          rsi = size of array (count)
; returns: rax = index of first occurrence of the minimum value, or -1 if empty
; -----------------------------------------------------------------------------
global umath_min_i64_reduce_index
umath_min_i64_reduce_index:
    mov     rax, -1
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done

    xor     rax, rax            ; min_index = 0
    mov     r8, [rdi]           ; min_val = src[0]
    
    mov     rcx, 1              ; current index = 1
    dec     rsi
    jz      .done

.loop_reduce:
    mov     r9, [rdi + rcx * 8]
    
    ; is current value < min_val? (r9 < r8)
    cmp     r9, r8
    jge     .next_item

    ; update minimum
    mov     r8, r9
    mov     rax, rcx            ; min_index = current index

.next_item:
    inc     rcx
    dec     rsi
    jnz     .loop_reduce

.done:
    ret

; -----------------------------------------------------------------------------
; umath_min_i64_inplace_clip - clips all elements in array in-place to not exceed threshold
; args:    rdi = buffer pointer (buf)
;          rsi = size of array (count)
;          rdx = threshold value
; returns: void
; -----------------------------------------------------------------------------
global umath_min_i64_inplace_clip
umath_min_i64_inplace_clip:
    test    rdi, rdi
    jz      .done_clip
    test    rsi, rsi
    jz      .done_clip

    ; broadcast threshold to YMM15 (for vector path, AVX2)
    vmovq   xmm15, rdx
    vpbroadcastq ymm15, xmm15

    cmp     rsi, 8
    sub     rsp, 8              ; keep stack aligned

.check_size:
    jb      .single_ints

    mov     rcx, rsi
    shr     rcx, 3

.loop_unrolled:
    vmovdqu ymm0, [rdi]
    vmovdqu ymm1, [rdi + 32]

    ; clip elements: val = min(val, threshold)
    ; vpblendvb expects mask in the third operand or implicit (in AVX2 it uses mask register or vblendvpd/vblendvps/vpblendvb)
    ; let's do: mask = ymm0 > ymm15
    vpcmpgtq ymm2, ymm0, ymm15
    vpcmpgtq ymm3, ymm1, ymm15

    vpblendvb ymm0, ymm0, ymm15, ymm2
    vpblendvb ymm1, ymm1, ymm15, ymm3

    vmovdqu [rdi], ymm0
    vmovdqu [rdi + 32], ymm1

    add     rdi, 64
    dec     rcx
    jnz     .loop_unrolled

    and     rsi, 7
    jz      .done_clip_pop

.single_ints:
    cmp     rsi, 2
    jb      .residuals

    mov     rcx, rsi
    shr     rcx, 1

.loop_vector:
    vmovdqu xmm0, [rdi]
    vpcmpgtq xmm1, xmm0, xmm15
    vpblendvb xmm0, xmm0, xmm15, xmm1
    vmovdqu [rdi], xmm0
    add     rdi, 16
    dec     rcx
    jnz     .loop_vector

    and     rsi, 1
    jz      .done_clip_pop

.residuals:
    mov     rax, [rdi]
    cmp     rax, rdx
    cmovg   rax, rdx
    mov     [rdi], rax
    add     rdi, 8
    dec     rsi
    jnz     .residuals

.done_clip_pop:
    add     rsp, 8
.done_clip:
    vzeroupper
    ret

; -----------------------------------------------------------------------------
; umath_min_i64_reduce_range - reduce sub-segment of array to its minimum value
; args:    rdi = source pointer (src)
;          rsi = start index
;          rdx = end index (exclusive)
; returns: rax = minimum value in range, or 0 if invalid
; -----------------------------------------------------------------------------
global umath_min_i64_reduce_range
umath_min_i64_reduce_range:
    xor     rax, rax
    test    rdi, rdi
    jz      .done_range
    cmp     rsi, rdx
    jae     .done_range         ; invalid range

    ; calculate size: rcx = end - start
    mov     rcx, rdx
    sub     rcx, rsi

    ; offset pointer: rdi = src + start * 8
    lea     rdi, [rdi + rsi * 8]

    mov     rax, [rdi]          ; initial minimum
    add     rdi, 8
    dec     rcx
    jz      .done_range

.loop_reduce:
    mov     r8, [rdi]
    cmp     rax, r8
    cmovg   rax, r8
    add     rdi, 8
    dec     rcx
    jnz     .loop_reduce

.done_range:
    ret

%endif ; GUARD_LIB_UMATH_SCALAR_MIN_I64_ASM
