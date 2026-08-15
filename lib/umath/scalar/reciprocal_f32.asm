%ifndef GUARD_LIB_UMATH_SCALAR_RECIPROCAL_F32_ASM
%define GUARD_LIB_UMATH_SCALAR_RECIPROCAL_F32_ASM
; =============================================================================
; umath - unified math library
; scalar/reciprocal_f32.asm - single-precision float reciprocal implementations
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; Performance Optimizations:
;   - Vectorized full-precision reciprocal unrolled 4x (using SSE divps).
;   - Vectorized approximate reciprocal unrolled 4x (using SSE rcpps).
;   - Vectorized Newton-Raphson refined reciprocal (1 step: x * (2.0 - val * x)).
;   - In-place and copying reciprocal mappings.
; =============================================================================

bits 64

section .rodata
align 16
recipf32_one:      dd 1.0, 1.0, 1.0, 1.0
recipf32_two:      dd 2.0, 2.0, 2.0, 2.0

section .text

; -----------------------------------------------------------------------------
; umath_reciprocal_f32 - full-precision scalar float reciprocal (1.0 / val)
; args:    xmm0 = input value (val)
; returns: xmm0 = 1.0 / val
; -----------------------------------------------------------------------------
global umath_reciprocal_f32
umath_reciprocal_f32:
    movss   xmm1, [rel recipf32_one]
    divss   xmm1, xmm0          ; xmm1 = 1.0f / val
    movaps  xmm0, xmm1
    ret

; -----------------------------------------------------------------------------
; umath_reciprocal_f32_approx - fast approximate scalar float reciprocal
; args:    xmm0 = input value (val)
; returns: xmm0 = approx(1.0 / val) (approx 12-bit precision)
; -----------------------------------------------------------------------------
global umath_reciprocal_f32_approx
umath_reciprocal_f32_approx:
    rcpss   xmm0, xmm0          ; hardware approximate reciprocal
    ret

; -----------------------------------------------------------------------------
; umath_reciprocal_f32_refined - Newton-Raphson refined float reciprocal
; args:    xmm0 = input value (val)
; returns: xmm0 = refined(1.0 / val) (approx 24-bit full precision)
; -----------------------------------------------------------------------------
global umath_reciprocal_f32_refined
umath_reciprocal_f32_refined:
    rcpss   xmm1, xmm0          ; xmm1 = x0 (initial approximation)
    mulss   xmm0, xmm1          ; xmm0 = val * x0
    movss   xmm2, [rel recipf32_two]
    subss   xmm2, xmm0          ; xmm2 = 2.0 - val * x0
    mulss   xmm1, xmm2          ; xmm1 = x0 * (2.0 - val * x0)
    movaps  xmm0, xmm1
    ret

; -----------------------------------------------------------------------------
; umath_reciprocal_f32_array - compute full-precision reciprocal of an array of floats
; args:    rdi = destination pointer (dst)
;          rsi = source pointer (src)
;          rdx = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_reciprocal_f32_array
umath_reciprocal_f32_array:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done
    test    rdx, rdx
    jz      .done

    movups  xmm15, [rel recipf32_one]

    cmp     rdx, 16
    jb      .single_floats

    mov     rcx, rdx
    shr     rcx, 4              ; count of 16-float blocks

.loop_unrolled:
    ; Load 16 elements
    movups  xmm0, [rsi]
    movups  xmm1, [rsi + 16]
    movups  xmm2, [rsi + 32]
    movups  xmm3, [rsi + 48]

    ; Compute reciprocals: dst = 1.0 / src
    movups  xmm4, xmm15
    movups  xmm5, xmm15
    movups  xmm6, xmm15
    movups  xmm7, xmm15

    divps   xmm4, xmm0
    divps   xmm5, xmm1
    divps   xmm6, xmm2
    divps   xmm7, xmm3

    ; Store results
    movups  [rdi], xmm4
    movups  [rdi + 16], xmm5
    movups  [rdi + 32], xmm6
    movups  [rdi + 48], xmm7

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
    movups  xmm1, xmm15
    divps   xmm1, xmm0
    movups  [rdi], xmm1
    add     rsi, 16
    add     rdi, 16
    dec     rcx
    jnz     .loop_vector

    and     rdx, 3
    jz      .done

.residuals:
    movss   xmm0, [rsi]
    movss   xmm1, xmm15
    divss   xmm1, xmm0
    movss   [rdi], xmm1
    add     rsi, 4
    add     rdi, 4
    dec     rdx
    jnz     .residuals

.done:
    ret

; -----------------------------------------------------------------------------
; umath_reciprocal_f32_array_approx - compute fast approximate reciprocal of an array of floats
; args:    rdi = destination pointer (dst)
;          rsi = source pointer (src)
;          rdx = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_reciprocal_f32_array_approx
umath_reciprocal_f32_array_approx:
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

    rcpps   xmm0, xmm0
    rcpps   xmm1, xmm1
    rcpps   xmm2, xmm2
    rcpps   xmm3, xmm3

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
    rcpps   xmm0, xmm0
    movups  [rdi], xmm0
    add     rsi, 16
    add     rdi, 16
    dec     rcx
    jnz     .loop_vector

    and     rdx, 3
    jz      .done

.residuals:
    movss   xmm0, [rsi]
    rcpss   xmm0, xmm0
    movss   [rdi], xmm0
    add     rsi, 4
    add     rdi, 4
    dec     rdx
    jnz     .residuals

.done:
    ret

; -----------------------------------------------------------------------------
; umath_reciprocal_f32_array_refined - compute refined approximate reciprocal of an array of floats
; args:    rdi = destination pointer (dst)
;          rsi = source pointer (src)
;          rdx = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_reciprocal_f32_array_refined
umath_reciprocal_f32_array_refined:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done
    test    rdx, rdx
    jz      .done

    movups  xmm15, [rel recipf32_two]

    cmp     rdx, 16
    jb      .single_floats

    mov     rcx, rdx
    shr     rcx, 4

.loop_unrolled:
    movups  xmm0, [rsi]         ; val0
    movups  xmm1, [rsi + 16]    ; val1
    movups  xmm2, [rsi + 32]    ; val2
    movups  xmm3, [rsi + 48]    ; val3

    ; x = approx(1 / val)
    rcpps   xmm4, xmm0          ; x0
    rcpps   xmm5, xmm1          ; x1
    rcpps   xmm6, xmm2          ; x2
    rcpps   xmm7, xmm3          ; x3

    ; val * x
    movups  xmm8, xmm0
    movups  xmm9, xmm1
    movups  xmm10, xmm2
    movups  xmm11, xmm3
    mulps   xmm8, xmm4          ; val0 * x0
    mulps   xmm9, xmm5          ; val1 * x1
    mulps   xmm10, xmm6         ; val2 * x2
    mulps   xmm11, xmm7         ; val3 * x3

    ; 2.0 - val * x
    movups  xmm0, xmm15
    movups  xmm1, xmm15
    movups  xmm2, xmm15
    movups  xmm3, xmm15
    subps   xmm0, xmm8
    subps   xmm1, xmm9
    subps   xmm2, xmm10
    subps   xmm3, xmm11

    ; x * (2.0 - val * x)
    mulps   xmm4, xmm0
    mulps   xmm5, xmm1
    mulps   xmm6, xmm2
    mulps   xmm7, xmm3

    ; Store results
    movups  [rdi], xmm4
    movups  [rdi + 16], xmm5
    movups  [rdi + 32], xmm6
    movups  [rdi + 48], xmm7

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
    rcpps   xmm1, xmm0          ; x0
    movups  xmm2, xmm0
    mulps   xmm2, xmm1          ; val * x0
    movups  xmm3, xmm15
    subps   xmm3, xmm2          ; 2.0 - val * x0
    mulps   xmm1, xmm3          ; x0 * (2.0 - val * x0)
    movups  [rdi], xmm1
    add     rsi, 16
    add     rdi, 16
    dec     rcx
    jnz     .loop_vector

    and     rdx, 3
    jz      .done

.residuals:
    movss   xmm0, [rsi]
    rcpss   xmm1, xmm0
    mulss   xmm0, xmm1
    movss   xmm2, [rel recipf32_two]
    subss   xmm2, xmm0
    mulss   xmm1, xmm2
    movss   [rdi], xmm1
    add     rsi, 4
    add     rdi, 4
    dec     rdx
    jnz     .residuals

.done:
    ret

; -----------------------------------------------------------------------------
; umath_reciprocal_f32_inplace - in-place full-precision reciprocal of float array
; args:    rdi = buffer pointer (buf)
;          rsi = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_reciprocal_f32_inplace
umath_reciprocal_f32_inplace:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done

    movups  xmm15, [rel recipf32_one]

    cmp     rsi, 16
    jb      .single_floats

    mov     rcx, rsi
    shr     rcx, 4

.loop_unrolled:
    movups  xmm0, [rdi]
    movups  xmm1, [rdi + 16]
    movups  xmm2, [rdi + 32]
    movups  xmm3, [rdi + 48]

    movups  xmm4, xmm15
    movups  xmm5, xmm15
    movups  xmm6, xmm15
    movups  xmm7, xmm15

    divps   xmm4, xmm0
    divps   xmm5, xmm1
    divps   xmm6, xmm2
    divps   xmm7, xmm3

    movups  [rdi], xmm4
    movups  [rdi + 16], xmm5
    movups  [rdi + 32], xmm6
    movups  [rdi + 48], xmm7

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
    movups  xmm1, xmm15
    divps   xmm1, xmm0
    movups  [rdi], xmm1
    add     rdi, 16
    dec     rcx
    jnz     .loop_vector

    and     rsi, 3
    jz      .done

.residuals:
    movss   xmm0, [rdi]
    movss   xmm1, xmm15
    divss   xmm1, xmm0
    movss   [rdi], xmm1
    add     rdi, 4
    dec     rsi
    jnz     .residuals

.done:
    ret

; -----------------------------------------------------------------------------
; umath_reciprocal_f32_inplace_refined - in-place refined reciprocal of float array
; args:    rdi = buffer pointer (buf)
;          rsi = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_reciprocal_f32_inplace_refined
umath_reciprocal_f32_inplace_refined:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done

    movups  xmm15, [rel recipf32_two]

    cmp     rsi, 16
    jb      .single_floats

    mov     rcx, rsi
    shr     rcx, 4

.loop_unrolled:
    movups  xmm0, [rdi]         ; val0
    movups  xmm1, [rdi + 16]    ; val1
    movups  xmm2, [rdi + 32]    ; val2
    movups  xmm3, [rdi + 48]    ; val3

    rcpps   xmm4, xmm0          ; x0
    rcpps   xmm5, xmm1          ; x1
    rcpps   xmm6, xmm2          ; x2
    rcpps   xmm7, xmm3          ; x3

    movups  xmm8, xmm0
    movups  xmm9, xmm1
    movups  xmm10, xmm2
    movups  xmm11, xmm3
    mulps   xmm8, xmm4
    mulps   xmm9, xmm5
    mulps   xmm10, xmm6
    mulps   xmm11, xmm7

    movups  xmm0, xmm15
    movups  xmm1, xmm15
    movups  xmm2, xmm15
    movups  xmm3, xmm15
    subps   xmm0, xmm8
    subps   xmm1, xmm9
    subps   xmm2, xmm10
    subps   xmm3, xmm11

    mulps   xmm4, xmm0
    mulps   xmm5, xmm1
    mulps   xmm6, xmm2
    mulps   xmm7, xmm3

    movups  [rdi], xmm4
    movups  [rdi + 16], xmm5
    movups  [rdi + 32], xmm6
    movups  [rdi + 48], xmm7

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
    rcpps   xmm1, xmm0
    movups  xmm2, xmm0
    mulps   xmm2, xmm1
    movups  xmm3, xmm15
    subps   xmm3, xmm2
    mulps   xmm1, xmm3
    movups  [rdi], xmm1
    add     rdi, 16
    dec     rcx
    jnz     .loop_vector

    and     rsi, 3
    jz      .done

.residuals:
    movss   xmm0, [rdi]
    rcpss   xmm1, xmm0
    mulss   xmm0, xmm1
    movss   xmm2, [rel recipf32_two]
    subss   xmm2, xmm0
    mulss   xmm1, xmm2
    movss   [rdi], xmm1
    add     rdi, 4
    dec     rsi
    jnz     .residuals

.done:
    ret

%endif ; GUARD_LIB_UMATH_SCALAR_RECIPROCAL_F32_ASM
