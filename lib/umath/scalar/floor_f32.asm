%ifndef GUARD_LIB_UMATH_SCALAR_FLOOR_F32_ASM
%define GUARD_LIB_UMATH_SCALAR_FLOOR_F32_ASM
; =============================================================================
; umath - unified math library
; scalar/floor_f32.asm - single-precision float floor implementations
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; Performance Optimizations:
;   - Vectorized element-wise floor mapping unrolled 4x (using SSE4.1 roundps).
;   - In-place and copying floor mappings.
;   - Conversion from float array to signed 32-bit integer array.
;   - Fractional part isolation (returning positive values in [0.0, 1.0)).
;   - Strict integer check utility with NaN guard.
; =============================================================================

bits 64
section .text

; -----------------------------------------------------------------------------
; umath_floor_f32 - floor a scalar float (round down)
; args:    xmm0 = input value (val)
; returns: xmm0 = floored value
; -----------------------------------------------------------------------------
global umath_floor_f32
umath_floor_f32:
    roundss xmm0, xmm0, 1       ; round down (mode 1)
    ret

; -----------------------------------------------------------------------------
; umath_floor_f32_to_i32 - floor float and convert to 32-bit integer
; args:    xmm0 = input value (val)
; returns: eax = floored 32-bit integer
; -----------------------------------------------------------------------------
global umath_floor_f32_to_i32
umath_floor_f32_to_i32:
    roundss xmm0, xmm0, 1       ; guarantee floor rounding
    cvtss2si eax, xmm0          ; convert scalar float to signed 32-bit integer
    ret

; -----------------------------------------------------------------------------
; umath_floor_f32_array - floor an array of floats
; args:    rdi = destination pointer (dst)
;          rsi = source pointer (src)
;          rdx = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_floor_f32_array
umath_floor_f32_array:
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

    ; Floor round (mode 1)
    roundps xmm0, xmm0, 1
    roundps xmm1, xmm1, 1
    roundps xmm2, xmm2, 1
    roundps xmm3, xmm3, 1

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
    roundps xmm0, xmm0, 1
    movups  [rdi], xmm0
    add     rsi, 16
    add     rdi, 16
    dec     rcx
    jnz     .loop_vector

    and     rdx, 3
    jz      .done

.residuals:
    movss   xmm0, [rsi]
    roundss xmm0, xmm0, 1
    movss   [rdi], xmm0
    add     rsi, 4
    add     rdi, 4
    dec     rdx
    jnz     .residuals

.done:
    ret

; -----------------------------------------------------------------------------
; umath_floor_f32_inplace - in-place floored mapping of float array
; args:    rdi = buffer pointer (buf)
;          rsi = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_floor_f32_inplace
umath_floor_f32_inplace:
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

    roundps xmm0, xmm0, 1
    roundps xmm1, xmm1, 1
    roundps xmm2, xmm2, 1
    roundps xmm3, xmm3, 1

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
    roundps xmm0, xmm0, 1
    movups  [rdi], xmm0
    add     rdi, 16
    dec     rcx
    jnz     .loop_vector

    and     rsi, 3
    jz      .done

.residuals:
    movss   xmm0, [rdi]
    roundss xmm0, xmm0, 1
    movss   [rdi], xmm0
    add     rdi, 4
    dec     rsi
    jnz     .residuals

.done:
    ret

; -----------------------------------------------------------------------------
; umath_floor_f32_fractional - compute positive fractional part of scalar float
;                              frac = val - floor(val) (always in [0.0, 1.0))
; args:    xmm0 = input value (val)
; returns: xmm0 = positive fractional part
; -----------------------------------------------------------------------------
global umath_floor_f32_fractional
umath_floor_f32_fractional:
    movaps  xmm1, xmm0          ; xmm1 = val
    roundss xmm0, xmm0, 1       ; xmm0 = floor(val)
    subss   xmm1, xmm0          ; xmm1 = val - floor(val)
    movaps  xmm0, xmm1          ; xmm0 = fractional part
    ret

; -----------------------------------------------------------------------------
; umath_floor_f32_to_i32_array - floor and convert array of floats to array of signed 32-bit ints
; args:    rdi = destination pointer (dst_i32)
;          rsi = source pointer (src_f32)
;          rdx = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_floor_f32_to_i32_array
umath_floor_f32_to_i32_array:
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

    ; Floor round
    roundps xmm0, xmm0, 1
    roundps xmm1, xmm1, 1
    roundps xmm2, xmm2, 1
    roundps xmm3, xmm3, 1

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
    roundps xmm0, xmm0, 1
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
    roundss xmm0, xmm0, 1
    cvtss2si eax, xmm0
    mov     [rdi], eax
    add     rsi, 4
    add     rdi, 4
    dec     rdx
    jnz     .residuals

.done:
    ret

; -----------------------------------------------------------------------------
; umath_floor_f32_is_integer - check if float is an integer
; args:    xmm0 = input value (val)
; returns: eax = 1 if val is an integer (val == floor(val)), 0 otherwise/NaN
; -----------------------------------------------------------------------------
global umath_floor_f32_is_integer
umath_floor_f32_is_integer:
    movaps  xmm1, xmm0
    roundss xmm0, xmm0, 1       ; xmm0 = floor(val)
    ucomiss xmm0, xmm1          ; compare floor(val) vs val
    jne     .not_int            ; if not equal, not an integer
    jp      .not_int            ; NaN guard

    mov     eax, 1
    ret

.not_int:
    xor     eax, eax
    ret

%endif ; GUARD_LIB_UMATH_SCALAR_FLOOR_F32_ASM
