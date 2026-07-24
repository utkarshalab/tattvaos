; =============================================================================
; umath - unified math library
; scalar/max_f64.asm - double-precision float maximum implementations
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; IEEE 754 Maximum Specification:
;   - Standard maximum: return b if b > a, else a.
;   - Strict IEEE-754 maximum (umath_max_f64_ieee):
;     1. NaN Propagation: if one operand is NaN and the other is a number,
;        the number must be returned. If both are NaN, return NaN.
;     2. Signed Zeros: +0.0 is defined as strictly greater than -0.0.
;        If inputs are +0.0 and -0.0, the maximum must return +0.0.
;
; Performance Optimizations:
;   - Vectorized element-wise maximums unrolled 4x.
;   - Argument reduction (argmax index) with branchless checks.
;   - Inplace clamping/clipping for activation functions (e.g. LeakyReLU/ReLU).
; =============================================================================

bits 64
section .text

; 128-bit absolute value mask (clears bit 63 of each 64-bit slot)
align 16
mask_abs_f64:
    dq 0x7FFFFFFFFFFFFFFF, 0x7FFFFFFFFFFFFFFF

; -----------------------------------------------------------------------------
; umath_max_f64 - scalar double-precision float maximum
; args:    xmm0 = a
;          xmm1 = b
; returns: xmm0 = max(a, b)
; -----------------------------------------------------------------------------
global umath_max_f64
umath_max_f64:
    maxsd   xmm0, xmm1
    ret

; -----------------------------------------------------------------------------
; umath_max_f64_ieee - strict IEEE-754 compliant double maximum
; args:    xmm0 = a
;          xmm1 = b
; returns: xmm0 = max(a, b) matching NaN propagation and signed zero rules
; -----------------------------------------------------------------------------
global umath_max_f64_ieee
umath_max_f64_ieee:
    ; Check if either input is NaN using unordered comparison
    ucomisd xmm0, xmm1
    jp      .handle_nan         ; Parity flag (PF) set implies unordered (NaN)

    ; Compare values
    ucomisd xmm0, xmm1
    ja      .a_greater          ; a > b -> return a
    jb      .b_greater          ; a < b -> return b

    ; If they are equal, check for signed zeros (+0.0 vs -0.0)
    ; Bitwise AND the registers: if one is +0.0 (sign bit clear) and the other
    ; is -0.0 (sign bit set), the AND result will clear the sign bit, yielding
    ; +0.0, which is the correct maximum.
    andpd   xmm0, xmm1
    ret

.a_greater:
    ; xmm0 already contains a
    ret

.b_greater:
    movsd   xmm0, xmm1          ; return b
    ret

.handle_nan:
    ; Identify which input is NaN
    ucomisd xmm0, xmm0
    jp      .a_is_nan           ; a is NaN

    ; b must be NaN, return a
    ret

.a_is_nan:
    ucomisd xmm1, xmm1
    jp      .both_nan           ; both are NaN

    ; only a is NaN, return b
    movsd   xmm0, xmm1
    ret

.both_nan:
    ; return NaN (xmm0 is already NaN)
    ret

; -----------------------------------------------------------------------------
; umath_max_f64_array - compute element-wise maximum of two double arrays
; args:    rdi = destination pointer (dst)
;          rsi = source pointer a (src_a)
;          rdx = source pointer b (src_b)
;          rcx = size of arrays (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_max_f64_array
umath_max_f64_array:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done
    test    rdx, rdx
    jz      .done
    test    rcx, rcx
    jz      .done

    cmp     rcx, 8
    jb      .single_doubles

    mov     r8, rcx
    shr     r8, 3               ; count of 8-double (64-byte) blocks

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
    maxpd   xmm0, xmm4
    maxpd   xmm1, xmm5
    maxpd   xmm2, xmm6
    maxpd   xmm3, xmm7

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

    and     rcx, 7
    jz      .done

.single_doubles:
    cmp     rcx, 2
    jb      .residuals

    mov     r8, rcx
    shr     r8, 1

.loop_vector:
    movups  xmm0, [rsi]
    movups  xmm1, [rdx]
    maxpd   xmm0, xmm1
    movups  [rdi], xmm0
    add     rsi, 16
    add     rdx, 16
    add     rdi, 16
    dec     r8
    jnz     .loop_vector

    and     rcx, 1
    jz      .done

.residuals:
    movsd   xmm0, [rsi]
    movsd   xmm1, [rdx]
    maxsd   xmm0, xmm1
    movsd   [rdi], xmm0
    add     rsi, 8
    add     rdx, 8
    add     rdi, 8
    dec     rcx
    jnz     .residuals

.done:
    ret

; -----------------------------------------------------------------------------
; umath_max_f64_reduce - reduce an array of doubles to its maximum value
; args:    rdi = source pointer (src)
;          rsi = size of array (count)
; returns: xmm0 = maximum double value in array
; -----------------------------------------------------------------------------
global umath_max_f64_reduce
umath_max_f64_reduce:
    xorps   xmm0, xmm0
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done

    movsd   xmm0, [rdi]
    add     rdi, 8
    dec     rsi
    jz      .done

.loop_reduce:
    movsd   xmm1, [rdi]
    maxsd   xmm0, xmm1
    add     rdi, 8
    dec     rsi
    jnz     .loop_reduce
.done:
    ret

; -----------------------------------------------------------------------------
; umath_max_f64_reduce_index - reduce array of doubles to index of maximum (argmax)
; args:    rdi = source pointer (src)
;          rsi = size of array (count)
; returns: rax = index of first occurrence of the maximum value, or -1 if empty
; -----------------------------------------------------------------------------
global umath_max_f64_reduce_index
umath_max_f64_reduce_index:
    mov     rax, -1
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done

    xor     rax, rax            ; max_index = 0
    movsd   xmm0, [rdi]         ; max_val = src[0]
    
    mov     rcx, 1
    dec     rsi
    jz      .done

.loop_reduce:
    movsd   xmm1, [rdi + rcx * 8]
    
    ; is current value > max_val? (xmm1 > xmm0)
    ucomisd xmm1, xmm0
    jbe     .next_item
    jp      .next_item          ; skip NaN

    ; update maximum
    movsd   xmm0, xmm1
    mov     rax, rcx

.next_item:
    inc     rcx
    dec     rsi
    jnz     .loop_reduce

.done:
    ret

; -----------------------------------------------------------------------------
; umath_max_f64_inplace_clip - clips elements in-place to not be less than threshold
; args:    rdi = buffer pointer (buf)
;          rsi = size of array (count)
;          xmm0 = threshold value
; returns: void
; -----------------------------------------------------------------------------
global umath_max_f64_inplace_clip
umath_max_f64_inplace_clip:
    test    rdi, rdi
    jz      .done_clip
    test    rsi, rsi
    jz      .done_clip

    ; broadcast threshold across all 2 slots of XMM15
    shufpd  xmm0, xmm0, 0
    movapd  xmm15, xmm0

    cmp     rsi, 8
    jb      .single_doubles

    mov     rcx, rsi
    shr     rcx, 3

.loop_unrolled:
    movups  xmm0, [rdi]
    movups  xmm1, [rdi + 16]
    movups  xmm2, [rdi + 32]
    movups  xmm3, [rdi + 48]

    ; elements = max(elements, threshold)
    maxpd   xmm0, xmm15
    maxpd   xmm1, xmm15
    maxpd   xmm2, xmm15
    maxpd   xmm3, xmm15

    movups  [rdi], xmm0
    movups  [rdi + 16], xmm1
    movups  [rdi + 32], xmm2
    movups  [rdi + 48], xmm3

    add     rdi, 64
    dec     rcx
    jnz     .loop_unrolled

    and     rsi, 7
    jz      .done_clip

.single_doubles:
    cmp     rsi, 2
    jb      .residuals

    mov     rcx, rsi
    shr     rcx, 1

.loop_vector:
    movups  xmm0, [rdi]
    maxpd   xmm0, xmm15
    movups  [rdi], xmm0
    add     rdi, 16
    dec     rcx
    jnz     .loop_vector

    and     rsi, 1
    jz      .done_clip

.residuals:
    movsd   xmm0, [rdi]
    maxsd   xmm0, xmm15
    movsd   [rdi], xmm0
    add     rdi, 8
    dec     rsi
    jnz     .residuals

.done_clip:
    ret

; -----------------------------------------------------------------------------
; umath_max_f64_reduce_range - reduce sub-segment of array to its maximum value
; args:    rdi = source pointer (src)
;          rsi = start index
;          rdx = end index (exclusive)
; returns: xmm0 = maximum value in range, or 0 if invalid
; -----------------------------------------------------------------------------
global umath_max_f64_reduce_range
umath_max_f64_reduce_range:
    xorps   xmm0, xmm0
    test    rdi, rdi
    jz      .done_range
    cmp     rsi, rdx
    jae     .done_range         ; invalid range

    ; calculate count = end - start
    mov     rcx, rdx
    sub     rcx, rsi

    ; offset pointer = src + start * 8
    lea     rdi, [rdi + rsi * 8]

    movsd   xmm0, [rdi]
    add     rdi, 8
    dec     rcx
    jz      .done_range

.loop_reduce:
    movsd   xmm1, [rdi]
    maxsd   xmm0, xmm1
    add     rdi, 8
    dec     rcx
    jnz     .loop_reduce

.done_range:
    ret
