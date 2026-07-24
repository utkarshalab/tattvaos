; =============================================================================
; umath - unified math library
; scalar/ceil_f64.asm - double-precision float ceil implementations
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; Performance Optimizations:
;   - Vectorized element-wise ceil mapping unrolled 4x (using SSE4.1 roundpd).
;   - In-place and copying ceil mappings.
;   - Conversion from double array to signed 64-bit integer array.
;   - Fractional part isolation (returning negative values in (-1.0, 0.0]).
;   - Strict integer check utility with NaN guard.
; =============================================================================

bits 64
section .text

; -----------------------------------------------------------------------------
; umath_ceil_f64 - ceil a scalar double (round up)
; args:    xmm0 = input value (val)
; returns: xmm0 = ceiled value
; -----------------------------------------------------------------------------
global umath_ceil_f64
umath_ceil_f64:
    roundsd xmm0, xmm0, 2       ; round up (mode 2)
    ret

; -----------------------------------------------------------------------------
; umath_ceil_f64_to_i64 - ceil double and convert to 64-bit integer
; args:    xmm0 = input value (val)
; returns: rax = ceiled 64-bit integer
; -----------------------------------------------------------------------------
global umath_ceil_f64_to_i64
umath_ceil_f64_to_i64:
    roundsd xmm0, xmm0, 2       ; guarantee ceil rounding
    cvtsd2si rax, xmm0          ; convert scalar double to signed 64-bit integer
    ret

; -----------------------------------------------------------------------------
; umath_ceil_f64_array - ceil an array of doubles
; args:    rdi = destination pointer (dst)
;          rsi = source pointer (src)
;          rdx = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_ceil_f64_array
umath_ceil_f64_array:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done
    test    rdx, rdx
    jz      .done

    cmp     rdx, 8
    jb      .single_doubles

    mov     rcx, rdx
    shr     rcx, 3              ; count of 8-double blocks

.loop_unrolled:
    ; Load 8 doubles (4 xmm registers)
    movups  xmm0, [rsi]
    movups  xmm1, [rsi + 16]
    movups  xmm2, [rsi + 32]
    movups  xmm3, [rsi + 48]

    ; Ceil round (mode 2)
    roundpd xmm0, xmm0, 2
    roundpd xmm1, xmm1, 2
    roundpd xmm2, xmm2, 2
    roundpd xmm3, xmm3, 2

    ; Store results
    movups  [rdi], xmm0
    movups  [rdi + 16], xmm1
    movups  [rdi + 32], xmm2
    movups  [rdi + 48], xmm3

    add     rsi, 64
    add     rdi, 64
    dec     rcx
    jnz     .loop_unrolled

    and     rdx, 7
    jz      .done

.single_doubles:
    cmp     rdx, 2
    jb      .residuals

    mov     rcx, rdx
    shr     rcx, 1              ; count of 2-double vectors

.loop_vector:
    movups  xmm0, [rsi]
    roundpd xmm0, xmm0, 2
    movups  [rdi], xmm0
    add     rsi, 16
    add     rdi, 16
    dec     rcx
    jnz     .loop_vector

    and     rdx, 1
    jz      .done

.residuals:
    movsd   xmm0, [rsi]
    roundsd xmm0, xmm0, 2
    movsd   [rdi], xmm0
    add     rsi, 8
    add     rdi, 8
    dec     rdx
    jnz     .residuals

.done:
    ret

; -----------------------------------------------------------------------------
; umath_ceil_f64_inplace - in-place ceiled mapping of double array
; args:    rdi = buffer pointer (buf)
;          rsi = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_ceil_f64_inplace
umath_ceil_f64_inplace:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done

    cmp     rsi, 8
    jb      .single_doubles

    mov     rcx, rsi
    shr     rcx, 3

.loop_unrolled:
    movups  xmm0, [rdi]
    movups  xmm1, [rdi + 16]
    movups  xmm2, [rdi + 32]
    movups  xmm3, [rdi + 48]

    roundpd xmm0, xmm0, 2
    roundpd xmm1, xmm1, 2
    roundpd xmm2, xmm2, 2
    roundpd xmm3, xmm3, 2

    movups  [rdi], xmm0
    movups  [rdi + 16], xmm1
    movups  [rdi + 32], xmm2
    movups  [rdi + 48], xmm3

    add     rdi, 64
    dec     rcx
    jnz     .loop_unrolled

    and     rsi, 7
    jz      .done

.single_doubles:
    cmp     rsi, 2
    jb      .residuals

    mov     rcx, rsi
    shr     rcx, 1

.loop_vector:
    movups  xmm0, [rdi]
    roundpd xmm0, xmm0, 2
    movups  [rdi], xmm0
    add     rdi, 16
    dec     rcx
    jnz     .loop_vector

    and     rsi, 1
    jz      .done

.residuals:
    movsd   xmm0, [rdi]
    roundsd xmm0, xmm0, 2
    movsd   [rdi], xmm0
    add     rdi, 8
    dec     rsi
    jnz     .residuals

.done:
    ret

; -----------------------------------------------------------------------------
; umath_ceil_f64_fractional - compute negative fractional part of scalar double
;                             frac = val - ceil(val) (always in (-1.0, 0.0])
; args:    xmm0 = input value (val)
; returns: xmm0 = negative fractional part
; -----------------------------------------------------------------------------
global umath_ceil_f64_fractional
umath_ceil_f64_fractional:
    movapd  xmm1, xmm0          ; xmm1 = val
    roundsd xmm0, xmm0, 2       ; xmm0 = ceil(val)
    subsd   xmm1, xmm0          ; xmm1 = val - ceil(val)
    movapd  xmm0, xmm1          ; xmm0 = fractional part
    ret

; -----------------------------------------------------------------------------
; umath_ceil_f64_to_i64_array - ceil and convert array of doubles to array of signed 64-bit ints
; args:    rdi = destination pointer (dst_i64)
;          rsi = source pointer (src_f64)
;          rdx = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_ceil_f64_to_i64_array
umath_ceil_f64_to_i64_array:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done
    test    rdx, rdx
    jz      .done

    cmp     rdx, 4
    jb      .residuals

    mov     rcx, rdx
    shr     rcx, 2              ; count of 4-double blocks (32 bytes)

.loop_unrolled:
    movups  xmm0, [rsi]         ; xmm0 = [val1, val0]
    movups  xmm1, [rsi + 16]    ; xmm1 = [val3, val2]

    ; Ceil round
    roundpd xmm0, xmm0, 2
    roundpd xmm1, xmm1, 2

    ; Extract and convert val0
    cvtsd2si rax, xmm0
    mov     [rdi], rax

    ; Extract and convert val1
    movhlps xmm2, xmm0
    cvtsd2si rax, xmm2
    mov     [rdi + 8], rax

    ; Extract and convert val2
    cvtsd2si rax, xmm1
    mov     [rdi + 16], rax

    ; Extract and convert val3
    movhlps xmm2, xmm1
    cvtsd2si rax, xmm2
    mov     [rdi + 24], rax

    add     rsi, 32
    add     rdi, 32
    dec     rcx
    jnz     .loop_unrolled

    and     rdx, 3
    jz      .done

.residuals:
    movsd   xmm0, [rsi]
    roundsd xmm0, xmm0, 2
    cvtsd2si rax, xmm0
    mov     [rdi], rax
    add     rsi, 8
    add     rdi, 8
    dec     rdx
    jnz     .residuals

.done:
    ret

; -----------------------------------------------------------------------------
; umath_ceil_f64_is_integer - check if double is an integer
; args:    xmm0 = input value (val)
; returns: eax = 1 if val is an integer (val == ceil(val)), 0 otherwise/NaN
; -----------------------------------------------------------------------------
global umath_ceil_f64_is_integer
umath_ceil_f64_is_integer:
    movapd  xmm1, xmm0
    roundsd xmm0, xmm0, 2       ; xmm0 = ceil(val)
    ucomisd xmm0, xmm1          ; compare ceil(val) vs val
    jne     .not_int            ; if not equal, not an integer
    jp      .not_int            ; NaN guard

    mov     eax, 1
    ret

.not_int:
    xor     eax, eax
    ret
