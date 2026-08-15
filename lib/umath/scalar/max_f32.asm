%ifndef GUARD_LIB_UMATH_SCALAR_MAX_F32_ASM
%define GUARD_LIB_UMATH_SCALAR_MAX_F32_ASM
; =============================================================================
; umath - unified math library
; scalar/max_f32.asm - single-precision float maximum implementations
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; IEEE 754 Maximum Specification:
;   - Standard maximum: return b if b > a, else a.
;   - Strict IEEE-754 maximum (umath_max_f32_ieee):
;     1. NaN Propagation: if one operand is NaN and the other is a number,
;        the number must be returned. If both are NaN, return NaN.
;     2. Signed Zeros: +0.0 is defined as strictly greater than -0.0.
;        If inputs are +0.0 and -0.0, the maximum must return +0.0.
;
; Performance Optimizations:
;   - Vectorized element-wise maximums unrolled 4x.
;   - Argument reduction (argmax index) with branchless checks.
;   - Inplace clamping/clipping for activation functions (e.g. ReLU).
; =============================================================================

bits 64
section .text

; 128-bit absolute value mask (clears bit 31 of each 32-bit slot)
align 16
maxf32_abs_mask:
    dd 0x7FFFFFFF, 0x7FFFFFFF, 0x7FFFFFFF, 0x7FFFFFFF

; -----------------------------------------------------------------------------
; umath_max_f32 - scalar single-precision float maximum
; args:    xmm0 = a
;          xmm1 = b
; returns: xmm0 = max(a, b)
; -----------------------------------------------------------------------------
global umath_max_f32
umath_max_f32:
    maxss   xmm0, xmm1
    ret

; -----------------------------------------------------------------------------
; umath_max_f32_ieee - strict IEEE-754 compliant float maximum
; args:    xmm0 = a
;          xmm1 = b
; returns: xmm0 = max(a, b) matching NaN propagation and signed zero rules
; -----------------------------------------------------------------------------
global umath_max_f32_ieee
umath_max_f32_ieee:
    ; Check if either input is NaN using unordered comparison
    ucomiss xmm0, xmm1
    jp      .handle_nan         ; Parity flag (PF) set implies unordered (NaN)

    ; Compare values
    ucomiss xmm0, xmm1
    ja      .a_greater          ; a > b -> return a
    jb      .b_greater          ; a < b -> return b

    ; If they are equal, check for signed zeros (+0.0 vs -0.0)
    ; Bitwise AND the registers: if one is +0.0 (sign bit clear) and the other
    ; is -0.0 (sign bit set), the AND result will clear the sign bit, yielding
    ; +0.0, which is the correct maximum.
    andps   xmm0, xmm1
    ret

.a_greater:
    ; xmm0 already contains a
    ret

.b_greater:
    movss   xmm0, xmm1          ; return b
    ret

.handle_nan:
    ; Identify which input is NaN
    ucomiss xmm0, xmm0
    jp      .a_is_nan           ; a is NaN

    ; b must be NaN, return a
    ret

.a_is_nan:
    ucomiss xmm1, xmm1
    jp      .both_nan           ; both are NaN

    ; only a is NaN, return b
    movss   xmm0, xmm1
    ret

.both_nan:
    ; return NaN (xmm0 is already NaN)
    ret

; -----------------------------------------------------------------------------
; umath_max_f32_array - compute element-wise maximum of two float arrays
; args:    rdi = destination pointer (dst)
;          rsi = source pointer a (src_a)
;          rdx = source pointer b (src_b)
;          rcx = size of arrays (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_max_f32_array
umath_max_f32_array:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done
    test    rdx, rdx
    jz      .done
    test    rcx, rcx
    jz      .done

    cmp     rcx, 16
    jb      .single_floats

    mov     r8, rcx
    shr     r8, 4               ; count of 16-float blocks

.loop_unrolled:
    movups  xmm0, [rsi]
    movups  xmm1, [rsi + 16]
    movups  xmm2, [rsi + 32]
    movups  xmm3, [rsi + 48]

    movups  xmm4, [rdx]
    movups  xmm5, [rdx + 16]
    movups  xmm6, [rdx + 32]
    movups  xmm7, [rdx + 48]

    ; Element-wise maximums
    maxps   xmm0, xmm4
    maxps   xmm1, xmm5
    maxps   xmm2, xmm6
    maxps   xmm3, xmm7

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

    and     rcx, 15
    jz      .done

.single_floats:
    cmp     rcx, 4
    jb      .residuals

    mov     r8, rcx
    shr     r8, 2

.loop_vector:
    movups  xmm0, [rsi]
    movups  xmm1, [rdx]
    maxps   xmm0, xmm1
    movups  [rdi], xmm0
    add     rsi, 16
    add     rdx, 16
    add     rdi, 16
    dec     r8
    jnz     .loop_vector

    and     rcx, 3
    jz      .done

.residuals:
    movss   xmm0, [rsi]
    movss   xmm1, [rdx]
    maxss   xmm0, xmm1
    movss   [rdi], xmm0
    add     rsi, 4
    add     rdx, 4
    add     rdi, 4
    dec     rcx
    jnz     .residuals

.done:
    ret

; -----------------------------------------------------------------------------
; umath_max_f32_reduce - reduce an array of floats to its maximum value
; args:    rdi = source pointer (src)
;          rsi = size of array (count)
; returns: xmm0 = maximum float value in array
; -----------------------------------------------------------------------------
global umath_max_f32_reduce
umath_max_f32_reduce:
    xorps   xmm0, xmm0
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done

    movss   xmm0, [rdi]
    add     rdi, 4
    dec     rsi
    jz      .done

.loop_reduce:
    movss   xmm1, [rdi]
    maxss   xmm0, xmm1
    add     rdi, 4
    dec     rsi
    jnz     .loop_reduce
.done:
    ret

; -----------------------------------------------------------------------------
; umath_max_f32_reduce_index - reduce array of floats to index of maximum (argmax)
; args:    rdi = source pointer (src)
;          rsi = size of array (count)
; returns: rax = index of first occurrence of the maximum value, or -1 if empty
; -----------------------------------------------------------------------------
global umath_max_f32_reduce_index
umath_max_f32_reduce_index:
    mov     rax, -1
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done

    xor     rax, rax            ; max_index = 0
    movss   xmm0, [rdi]         ; max_val = src[0]
    
    mov     rcx, 1
    dec     rsi
    jz      .done

.loop_reduce:
    movss   xmm1, [rdi + rcx * 4]
    
    ; is current value > max_val? (xmm1 > xmm0)
    ucomiss xmm1, xmm0
    jbe     .next_item
    jp      .next_item          ; skip NaN

    ; update maximum
    movss   xmm0, xmm1
    mov     rax, rcx

.next_item:
    inc     rcx
    dec     rsi
    jnz     .loop_reduce

.done:
    ret

; -----------------------------------------------------------------------------
; umath_max_f32_inplace_clip - clips elements in-place to not be less than threshold (ReLU)
; args:    rdi = buffer pointer (buf)
;          rsi = size of array (count)
;          xmm0 = threshold value
; returns: void
; -----------------------------------------------------------------------------
global umath_max_f32_inplace_clip
umath_max_f32_inplace_clip:
    test    rdi, rdi
    jz      .done_clip
    test    rsi, rsi
    jz      .done_clip

    ; broadcast threshold across all 4 slots of XMM15
    shufps  xmm0, xmm0, 0
    movaps  xmm15, xmm0

    cmp     rsi, 16
    jb      .single_floats

    mov     rcx, rsi
    shr     rcx, 4

.loop_unrolled:
    movups  xmm0, [rdi]
    movups  xmm1, [rdi + 16]
    movups  xmm2, [rdi + 32]
    movups  xmm3, [rdi + 48]

    ; elements = max(elements, threshold)
    maxps   xmm0, xmm15
    maxps   xmm1, xmm15
    maxps   xmm2, xmm15
    maxps   xmm3, xmm15

    movups  [rdi], xmm0
    movups  [rdi + 16], xmm1
    movups  [rdi + 32], xmm2
    movups  [rdi + 48], xmm3

    add     rdi, 64
    dec     rcx
    jnz     .loop_unrolled

    and     rsi, 15
    jz      .done_clip

.single_floats:
    cmp     rsi, 4
    jb      .residuals

    mov     rcx, rsi
    shr     rcx, 2

.loop_vector:
    movups  xmm0, [rdi]
    maxps   xmm0, xmm15
    movups  [rdi], xmm0
    add     rdi, 16
    dec     rcx
    jnz     .loop_vector

    and     rsi, 3
    jz      .done_clip

.residuals:
    movss   xmm0, [rdi]
    maxss   xmm0, xmm15
    movss   [rdi], xmm0
    add     rdi, 4
    dec     rsi
    jnz     .residuals

.done_clip:
    ret

; -----------------------------------------------------------------------------
; umath_max_f32_reduce_range - reduce sub-segment of array to its maximum value
; args:    rdi = source pointer (src)
;          rsi = start index
;          rdx = end index (exclusive)
; returns: xmm0 = maximum value in range, or 0 if invalid
; -----------------------------------------------------------------------------
global umath_max_f32_reduce_range
umath_max_f32_reduce_range:
    xorps   xmm0, xmm0
    test    rdi, rdi
    jz      .done_range
    cmp     rsi, rdx
    jae     .done_range         ; invalid range

    ; calculate count = end - start
    mov     rcx, rdx
    sub     rcx, rsi

    ; offset pointer = src + start * 4
    lea     rdi, [rdi + rsi * 4]

    movss   xmm0, [rdi]
    add     rdi, 4
    dec     rcx
    jz      .done_range

.loop_reduce:
    movss   xmm1, [rdi]
    maxss   xmm0, xmm1
    add     rdi, 4
    dec     rcx
    jnz     .loop_reduce

.done_range:
    ret

%endif ; GUARD_LIB_UMATH_SCALAR_MAX_F32_ASM
