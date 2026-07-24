; =============================================================================
; umath - unified math library
; scalar/trunc_f32.asm - single-precision float truncation implementations
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; Performance Optimizations:
;   - Vectorized element-wise truncation unrolled 4x (using SSE4.1 roundps).
;   - In-place and copying truncation mappings.
;   - Conversion from float array to signed 32-bit integer array.
;   - Fractional part isolation (returning signed values matching input sign).
;   - Strict integer check utility with NaN guard.
; =============================================================================

bits 64
section .text

; -----------------------------------------------------------------------------
; umath_trunc_f32 - truncate a scalar float (round toward zero)
; args:    xmm0 = input value (val)
; returns: xmm0 = truncated value
; -----------------------------------------------------------------------------
global umath_trunc_f32
umath_trunc_f32:
    roundss xmm0, xmm0, 3       ; truncate (mode 3)
    ret

; -----------------------------------------------------------------------------
; umath_trunc_f32_to_i32 - truncate float and convert to signed 32-bit integer
; args:    xmm0 = input value (val)
; returns: eax = truncated signed 32-bit integer
; -----------------------------------------------------------------------------
global umath_trunc_f32_to_i32
umath_trunc_f32_to_i32:
    cvttss2si eax, xmm0         ; cvttss2si directly truncates float to integer
    ret

; -----------------------------------------------------------------------------
; umath_trunc_f32_array - truncate an array of floats
; args:    rdi = destination pointer (dst)
;          rsi = source pointer (src)
;          rdx = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_trunc_f32_array
umath_trunc_f32_array:
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

    ; Truncate round (mode 3)
    roundps xmm0, xmm0, 3
    roundps xmm1, xmm1, 3
    roundps xmm2, xmm2, 3
    roundps xmm3, xmm3, 3

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
    roundps xmm0, xmm0, 3
    movups  [rdi], xmm0
    add     rsi, 16
    add     rdi, 16
    dec     rcx
    jnz     .loop_vector

    and     rdx, 3
    jz      .done

.residuals:
    movss   xmm0, [rsi]
    roundss xmm0, xmm0, 3
    movss   [rdi], xmm0
    add     rsi, 4
    add     rdi, 4
    dec     rdx
    jnz     .residuals

.done:
    ret

; -----------------------------------------------------------------------------
; umath_trunc_f32_inplace - in-place truncated mapping of float array
; args:    rdi = buffer pointer (buf)
;          rsi = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_trunc_f32_inplace
umath_trunc_f32_inplace:
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

    roundps xmm0, xmm0, 3
    roundps xmm1, xmm1, 3
    roundps xmm2, xmm2, 3
    roundps xmm3, xmm3, 3

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
    roundps xmm0, xmm0, 3
    movups  [rdi], xmm0
    add     rdi, 16
    dec     rcx
    jnz     .loop_vector

    and     rsi, 3
    jz      .done

.residuals:
    movss   xmm0, [rdi]
    roundss xmm0, xmm0, 3
    movss   [rdi], xmm0
    add     rdi, 4
    dec     rsi
    jnz     .residuals

.done:
    ret

; -----------------------------------------------------------------------------
; umath_trunc_f32_fractional - compute fractional part of scalar float relative to trunc
;                              frac = val - trunc(val) (sign matches val)
; args:    xmm0 = input value (val)
; returns: xmm0 = fractional part
; -----------------------------------------------------------------------------
global umath_trunc_f32_fractional
umath_trunc_f32_fractional:
    movaps  xmm1, xmm0          ; xmm1 = val
    roundss xmm0, xmm0, 3       ; xmm0 = trunc(val)
    subss   xmm1, xmm0          ; xmm1 = val - trunc(val)
    movaps  xmm0, xmm1          ; xmm0 = fractional part
    ret

; -----------------------------------------------------------------------------
; umath_trunc_f32_to_i32_array - truncate and convert array of floats to array of signed 32-bit ints
; args:    rdi = destination pointer (dst_i32)
;          rsi = source pointer (src_f32)
;          rdx = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_trunc_f32_to_i32_array
umath_trunc_f32_to_i32_array:
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

    ; cvttps2dq directly converts and truncates float vector elements to signed 32-bit integer vector elements
    cvttps2dq xmm0, xmm0
    cvttps2dq xmm1, xmm1
    cvttps2dq xmm2, xmm2
    cvttps2dq xmm3, xmm3

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
    cvttps2dq xmm0, xmm0
    movups  [rdi], xmm0
    add     rsi, 16
    add     rdi, 16
    dec     rcx
    jnz     .loop_vector

    and     rdx, 3
    jz      .done

.residuals:
    movss   xmm0, [rsi]
    cvttss2si eax, xmm0
    mov     [rdi], eax
    add     rsi, 4
    add     rdi, 4
    dec     rdx
    jnz     .residuals

.done:
    ret

; -----------------------------------------------------------------------------
; umath_trunc_f32_is_integer - check if float is an integer
; args:    xmm0 = input value (val)
; returns: eax = 1 if val is an integer (val == trunc(val)), 0 otherwise/NaN
; -----------------------------------------------------------------------------
global umath_trunc_f32_is_integer
umath_trunc_f32_is_integer:
    movaps  xmm1, xmm0
    roundss xmm0, xmm0, 3       ; xmm0 = trunc(val)
    ucomiss xmm0, xmm1          ; compare trunc(val) vs val
    jne     .not_int
    jp      .not_int            ; NaN guard

    mov     eax, 1
    ret

.not_int:
    xor     eax, eax
    ret
