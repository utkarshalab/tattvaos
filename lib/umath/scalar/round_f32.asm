; =============================================================================
; umath - unified math library
; scalar/round_f32.asm - single-precision float round implementations
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; Performance Optimizations:
;   - Vectorized element-wise rounding unrolled 4x (using SSE4.1 roundps).
;   - In-place and copying round mappings.
;   - Conversion from float array to integer array using cvtps2dq.
;   - Dynamic rounding mode dispatcher.
;   - Fractional part isolation.
; =============================================================================

bits 64
section .text

; -----------------------------------------------------------------------------
; umath_round_f32 - round a scalar float to nearest integer (even)
; args:    xmm0 = input value (val)
; returns: xmm0 = rounded value
; -----------------------------------------------------------------------------
global umath_round_f32
umath_round_f32:
    roundss xmm0, xmm0, 0       ; round to nearest even (mode 0)
    ret

; -----------------------------------------------------------------------------
; umath_round_f32_to_i32 - round float and convert to 32-bit integer
; args:    xmm0 = input value (val)
; returns: eax = rounded 32-bit integer
; -----------------------------------------------------------------------------
global umath_round_f32_to_i32
umath_round_f32_to_i32:
    roundss xmm0, xmm0, 0       ; guarantee round to nearest even
    cvtss2si eax, xmm0          ; convert scalar float to signed 32-bit integer
    ret

; -----------------------------------------------------------------------------
; umath_round_f32_array - round an array of floats
; args:    rdi = destination pointer (dst)
;          rsi = source pointer (src)
;          rdx = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_round_f32_array
umath_round_f32_array:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done
    test    rdx, rdx
    jz      .done

    cmp     rdx, 16
    jb      .single_floats

    mov     rcx, rdx
    shr     rcx, 4              ; count of 16-float blocks

.loop_unrolled:
    ; Load 16 floats
    movups  xmm0, [rsi]
    movups  xmm1, [rsi + 16]
    movups  xmm2, [rsi + 32]
    movups  xmm3, [rsi + 48]

    ; Round to nearest (even)
    roundps xmm0, xmm0, 0
    roundps xmm1, xmm1, 0
    roundps xmm2, xmm2, 0
    roundps xmm3, xmm3, 0

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
    roundps xmm0, xmm0, 0
    movups  [rdi], xmm0
    add     rsi, 16
    add     rdi, 16
    dec     rcx
    jnz     .loop_vector

    and     rdx, 3
    jz      .done

.residuals:
    movss   xmm0, [rsi]
    roundss xmm0, xmm0, 0
    movss   [rdi], xmm0
    add     rsi, 4
    add     rdi, 4
    dec     rdx
    jnz     .residuals

.done:
    ret

; -----------------------------------------------------------------------------
; umath_round_f32_inplace - in-place rounding of float array
; args:    rdi = buffer pointer (buf)
;          rsi = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_round_f32_inplace
umath_round_f32_inplace:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done

    cmp     rsi, 16
    jb      .single_floats

    mov     rcx, rsi
    shr     rcx, 4

.loop_unrolled:
    movups  xmm0, [rdi]
    movups  xmm1, [rdi + 16]
    movups  xmm2, [rdi + 32]
    movups  xmm3, [rdi + 48]

    roundps xmm0, xmm0, 0
    roundps xmm1, xmm1, 0
    roundps xmm2, xmm2, 0
    roundps xmm3, xmm3, 0

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
    roundps xmm0, xmm0, 0
    movups  [rdi], xmm0
    add     rdi, 16
    dec     rcx
    jnz     .loop_vector

    and     rsi, 3
    jz      .done

.residuals:
    movss   xmm0, [rdi]
    roundss xmm0, xmm0, 0
    movss   [rdi], xmm0
    add     rdi, 4
    dec     rsi
    jnz     .residuals

.done:
    ret

; -----------------------------------------------------------------------------
; umath_round_f32_with_mode - round a scalar float using specified rounding mode
; args:    xmm0 = input value (val)
;          edi = rounding mode immediate:
;                0 = round to nearest (even)
;                1 = round down (floor)
;                2 = round up (ceil)
;                3 = round toward zero (trunc)
; returns: xmm0 = rounded value
; -----------------------------------------------------------------------------
global umath_round_f32_with_mode
umath_round_f32_with_mode:
    cmp     edi, 0
    je      .mode_0
    cmp     edi, 1
    je      .mode_1
    cmp     edi, 2
    je      .mode_2
    cmp     edi, 3
    je      .mode_3
    ret                         ; invalid mode, return input unmodified

.mode_0:
    roundss xmm0, xmm0, 0
    ret
.mode_1:
    roundss xmm0, xmm0, 1
    ret
.mode_2:
    roundss xmm0, xmm0, 2
    ret
.mode_3:
    roundss xmm0, xmm0, 3
    ret

; -----------------------------------------------------------------------------
; umath_round_f32_to_i32_array - round and convert array of floats to array of signed 32-bit ints
; args:    rdi = destination pointer (dst_i32)
;          rsi = source pointer (src_f32)
;          rdx = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_round_f32_to_i32_array
umath_round_f32_to_i32_array:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done
    test    rdx, rdx
    jz      .done

    cmp     rdx, 16
    jb      .single_floats

    mov     rcx, rdx
    shr     rcx, 4

.loop_unrolled:
    movups  xmm0, [rsi]
    movups  xmm1, [rsi + 16]
    movups  xmm2, [rsi + 32]
    movups  xmm3, [rsi + 48]

    ; Round to nearest even
    roundps xmm0, xmm0, 0
    roundps xmm1, xmm1, 0
    roundps xmm2, xmm2, 0
    roundps xmm3, xmm3, 0

    ; Convert to signed 32-bit integer vectors
    cvtps2dq xmm0, xmm0
    cvtps2dq xmm1, xmm1
    cvtps2dq xmm2, xmm2
    cvtps2dq xmm3, xmm3

    ; Store as integer vectors
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
    roundps xmm0, xmm0, 0
    cvtps2dq xmm0, xmm0
    movups  [rdi], xmm0
    add     rsi, 16
    add     rdi, 16
    dec     rcx
    jnz     .loop_vector

    and     rdx, 3
    jz      .done

.residuals:
    movss   xmm0, [rsi]
    roundss xmm0, xmm0, 0
    cvtss2si eax, xmm0
    mov     [rdi], eax
    add     rsi, 4
    add     rdi, 4
    dec     rdx
    jnz     .residuals

.done:
    ret

; -----------------------------------------------------------------------------
; umath_round_f32_fractional - compute fractional part of a scalar float
;                              frac = val - round_to_nearest_even(val)
; args:    xmm0 = input value (val)
; returns: xmm0 = fractional part
; -----------------------------------------------------------------------------
global umath_round_f32_fractional
umath_round_f32_fractional:
    movaps  xmm1, xmm0          ; xmm1 = val
    roundss xmm0, xmm0, 0       ; xmm0 = round(val)
    subss   xmm1, xmm0          ; xmm1 = val - round(val)
    movaps  xmm0, xmm1          ; xmm0 = fractional part
    ret
