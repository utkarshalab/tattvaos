; =============================================================================
; umath - unified math library
; scalar/ceil_f32.asm - single-precision float ceil implementations
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; Performance Optimizations:
;   - Vectorized element-wise ceil mapping unrolled 4x (using SSE4.1 roundps).
;   - In-place and copying ceil mappings.
;   - Conversion from float array to signed 32-bit integer array.
;   - Fractional part isolation (returning negative values in (-1.0, 0.0]).
;   - Strict integer check utility with NaN guard.
; =============================================================================

bits 64
section .text

; -----------------------------------------------------------------------------
; umath_ceil_f32 - ceil a scalar float (round up)
; args:    xmm0 = input value (val)
; returns: xmm0 = ceiled value
; -----------------------------------------------------------------------------
global umath_ceil_f32
umath_ceil_f32:
    roundss xmm0, xmm0, 2       ; round up (mode 2)
    ret

; -----------------------------------------------------------------------------
; umath_ceil_f32_to_i32 - ceil float and convert to 32-bit integer
; args:    xmm0 = input value (val)
; returns: eax = ceiled 32-bit integer
; -----------------------------------------------------------------------------
global umath_ceil_f32_to_i32
umath_ceil_f32_to_i32:
    roundss xmm0, xmm0, 2       ; guarantee ceil rounding
    cvtss2si eax, xmm0          ; convert scalar float to signed 32-bit integer
    ret

; -----------------------------------------------------------------------------
; umath_ceil_f32_array - ceil an array of floats
; args:    rdi = destination pointer (dst)
;          rsi = source pointer (src)
;          rdx = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_ceil_f32_array
umath_ceil_f32_array:
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

    ; Ceil round (mode 2)
    roundps xmm0, xmm0, 2
    roundps xmm1, xmm1, 2
    roundps xmm2, xmm2, 2
    roundps xmm3, xmm3, 2

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
    roundps xmm0, xmm0, 2
    movups  [rdi], xmm0
    add     rsi, 16
    add     rdi, 16
    dec     rcx
    jnz     .loop_vector

    and     rdx, 3
    jz      .done

.residuals:
    movss   xmm0, [rsi]
    roundss xmm0, xmm0, 2
    movss   [rdi], xmm0
    add     rsi, 4
    add     rdi, 4
    dec     rdx
    jnz     .residuals

.done:
    ret

; -----------------------------------------------------------------------------
; umath_ceil_f32_inplace - in-place ceiled mapping of float array
; args:    rdi = buffer pointer (buf)
;          rsi = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_ceil_f32_inplace
umath_ceil_f32_inplace:
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

    roundps xmm0, xmm0, 2
    roundps xmm1, xmm1, 2
    roundps xmm2, xmm2, 2
    roundps xmm3, xmm3, 2

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
    roundps xmm0, xmm0, 2
    movups  [rdi], xmm0
    add     rdi, 16
    dec     rcx
    jnz     .loop_vector

    and     rsi, 3
    jz      .done

.residuals:
    movss   xmm0, [rdi]
    roundss xmm0, xmm0, 2
    movss   [rdi], xmm0
    add     rdi, 4
    dec     rsi
    jnz     .residuals

.done:
    ret

; -----------------------------------------------------------------------------
; umath_ceil_f32_fractional - compute negative fractional part of scalar float
;                             frac = val - ceil(val) (always in (-1.0, 0.0])
; args:    xmm0 = input value (val)
; returns: xmm0 = negative fractional part
; -----------------------------------------------------------------------------
global umath_ceil_f32_fractional
umath_ceil_f32_fractional:
    movaps  xmm1, xmm0          ; xmm1 = val
    roundss xmm0, xmm0, 2       ; xmm0 = ceil(val)
    subss   xmm1, xmm0          ; xmm1 = val - ceil(val)
    movaps  xmm0, xmm1          ; xmm0 = fractional part
    ret

; -----------------------------------------------------------------------------
; umath_ceil_f32_to_i32_array - ceil and convert array of floats to array of signed 32-bit ints
; args:    rdi = destination pointer (dst_i32)
;          rsi = source pointer (src_f32)
;          rdx = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_ceil_f32_to_i32_array
umath_ceil_f32_to_i32_array:
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

    ; Ceil round
    roundps xmm0, xmm0, 2
    roundps xmm1, xmm1, 2
    roundps xmm2, xmm2, 2
    roundps xmm3, xmm3, 2

    ; Convert to signed 32-bit integer vectors
    cvtps2dq xmm0, xmm0
    cvtps2dq xmm1, xmm1
    cvtps2dq xmm2, xmm2
    cvtps2dq xmm3, xmm3

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
    shr     rcx, 2

.loop_vector:
    movups  xmm0, [rsi]
    roundps xmm0, xmm0, 2
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
    roundss xmm0, xmm0, 2
    cvtss2si eax, xmm0
    mov     [rdi], eax
    add     rsi, 4
    add     rdi, 4
    dec     rdx
    jnz     .residuals

.done:
    ret

; -----------------------------------------------------------------------------
; umath_ceil_f32_is_integer - check if float is an integer
; args:    xmm0 = input value (val)
; returns: eax = 1 if val is an integer (val == ceil(val)), 0 otherwise/NaN
; -----------------------------------------------------------------------------
global umath_ceil_f32_is_integer
umath_ceil_f32_is_integer:
    movaps  xmm1, xmm0
    roundss xmm0, xmm0, 2       ; xmm0 = ceil(val)
    ucomiss xmm0, xmm1          ; compare ceil(val) vs val
    jne     .not_int            ; if not equal, not an integer
    jp      .not_int            ; NaN guard

    mov     eax, 1
    ret

.not_int:
    xor     eax, eax
    ret
