%ifndef GUARD_LIB_UMATH_SCALAR_ABS_I32_ASM
%define GUARD_LIB_UMATH_SCALAR_ABS_I32_ASM
; =============================================================================
; umath - unified math library
; scalar/abs_i32.asm - signed 32-bit integer absolute value implementations
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; Concepts:
;   - Branchless absolute value uses arithmetic shifts and bit XOR logic.
;   - Saturating absolute value prevents wrapping of INT32_MIN (0x80000000)
;     into itself, mapping it instead to INT32_MAX (0x7FFFFFFF).
;   - Vectorized loop utilizing the SSE4.1/AVX2 PABSD instruction.
;   - Vectorized saturating absolute array mapping.
; =============================================================================

bits 64
section .text

align 16
absi32_int32_min:    dd 0x80000000, 0x80000000, 0x80000000, 0x80000000
absi32_int32_max:    dd 0x7FFFFFFF, 0x7FFFFFFF, 0x7FFFFFFF, 0x7FFFFFFF

; -----------------------------------------------------------------------------
; umath_abs_i32 - scalar branchless 32-bit absolute value
; args:    edi = input signed 32-bit integer (val)
; returns: eax = absolute value
; -----------------------------------------------------------------------------
global umath_abs_i32
umath_abs_i32:
    mov     eax, edi
    cdq                         ; edx = sign bit of eax repeated (0 if positive, -1 if negative)
    xor     eax, edx            ; bitwise complement if negative, unchanged if positive
    sub     eax, edx            ; add 1 if negative (sub -1) to complete two's complement
    ret

; -----------------------------------------------------------------------------
; umath_abs_i32_sat - scalar saturating 32-bit absolute value
; args:    edi = input signed 32-bit integer (val)
; returns: eax = saturating absolute value (clamps INT32_MIN to INT32_MAX)
; -----------------------------------------------------------------------------
global umath_abs_i32_sat
umath_abs_i32_sat:
    cmp     edi, 0x80000000     ; check if val == INT32_MIN (-2147483648)
    je      .clamp

    mov     eax, edi
    cdq
    xor     eax, edx
    sub     eax, edx
    ret

.clamp:
    mov     eax, 0x7FFFFFFF     ; return INT32_MAX (2147483647)
    ret

; -----------------------------------------------------------------------------
; umath_abs_i32_array - compute absolute value for an array of 32-bit integers
; args:    rdi = destination pointer (dst)
;          rsi = source pointer (src)
;          rdx = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_abs_i32_array
umath_abs_i32_array:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done
    test    rdx, rdx
    jz      .done

    cmp     rdx, 16
    jb      .single_ints

    mov     rcx, rdx
    shr     rcx, 4              ; count of 16-integer (64-byte) blocks

.loop_unrolled:
    movups  xmm0, [rsi]
    movups  xmm1, [rsi + 16]
    movups  xmm2, [rsi + 32]
    movups  xmm3, [rsi + 48]

    pabsd   xmm0, xmm0
    pabsd   xmm1, xmm1
    pabsd   xmm2, xmm2
    pabsd   xmm3, xmm3

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

.single_ints:
    cmp     rdx, 4
    jb      .residuals

    mov     rcx, rdx
    shr     rcx, 2              ; count of 4-integer vectors

.loop_vector:
    movups  xmm0, [rsi]
    pabsd   xmm0, xmm0
    movups  [rdi], xmm0
    add     rsi, 16
    add     rdi, 16
    dec     rcx
    jnz     .loop_vector

    and     rdx, 3
    jz      .done

.residuals:
    mov     eax, [rsi]
    cdq
    xor     eax, edx
    sub     eax, edx
    mov     [rdi], eax
    add     rsi, 4
    add     rdi, 4
    dec     rdx
    jnz     .residuals

.done:
    ret

; -----------------------------------------------------------------------------
; umath_abs_i32_inplace - in-place absolute value for 32-bit integers
; args:    rdi = buffer pointer (buf)
;          rsi = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_abs_i32_inplace
umath_abs_i32_inplace:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done

    cmp     rsi, 16
    jb      .single_ints

    mov     rcx, rsi
    shr     rcx, 4

.loop_unrolled:
    movups  xmm0, [rdi]
    movups  xmm1, [rdi + 16]
    movups  xmm2, [rdi + 32]
    movups  xmm3, [rdi + 48]

    pabsd   xmm0, xmm0
    pabsd   xmm1, xmm1
    pabsd   xmm2, xmm2
    pabsd   xmm3, xmm3

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
    pabsd   xmm0, xmm0
    movups  [rdi], xmm0
    add     rdi, 16
    dec     rcx
    jnz     .loop_vector

    and     rsi, 3
    jz      .done

.residuals:
    mov     eax, [rdi]
    cdq
    xor     eax, edx
    sub     eax, edx
    mov     [rdi], eax
    add     rdi, 4
    dec     rsi
    jnz     .residuals

.done:
    ret

; -----------------------------------------------------------------------------
; umath_abs_i32_sat_array - compute saturating absolute value for 32-bit int array
; args:    rdi = destination pointer (dst)
;          rsi = source pointer (src)
;          rdx = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_abs_i32_sat_array
umath_abs_i32_sat_array:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done
    test    rdx, rdx
    jz      .done

    movups  xmm14, [rel absi32_int32_min]
    movups  xmm15, [rel absi32_int32_max]

    cmp     rdx, 16
    jb      .single_ints

    mov     rcx, rdx
    shr     rcx, 4

.loop_unrolled:
    movups  xmm0, [rsi]
    movups  xmm1, [rsi + 16]
    movups  xmm2, [rsi + 32]
    movups  xmm3, [rsi + 48]

    ; Generate masks where elements equal INT32_MIN
    movups  xmm4, xmm0
    movups  xmm5, xmm1
    movups  xmm6, xmm2
    movups  xmm7, xmm3
    pcmpeqd xmm4, xmm14
    pcmpeqd xmm5, xmm14
    pcmpeqd xmm6, xmm14
    pcmpeqd xmm7, xmm14

    ; Compute normal absolute values
    pabsd   xmm0, xmm0
    pabsd   xmm1, xmm1
    pabsd   xmm2, xmm2
    pabsd   xmm3, xmm3

    ; Blend: res = (abs(x) & ~mask) | (INT32_MAX & mask)
    ; In SSE, we can do it via:
    ; andn mask, abs -> clears where mask set
    ; and mask, max
    ; or together
    andnps  xmm4, xmm0
    andnps  xmm5, xmm1
    andnps  xmm6, xmm2
    andnps  xmm7, xmm3

    movups  xmm8, [rel absi32_int32_max]
    movups  xmm9, [rel absi32_int32_max]
    movups  xmm10, [rel absi32_int32_max]
    movups  xmm11, [rel absi32_int32_max]

    ; we need the original masks which were destroyed by andnps, or we can just reconstruct them.
    ; actually, let's load masks again or write them cleaner.
    ; let's do:
    ; mask_min = (src == INT_MIN)
    ; abs_val = pabsd(src)
    ; dst = blend(abs_val, INT_MAX, mask_min)
    ; under SSE4.1, we can use blendvps!
    ; blendvps xmm0, xmm15, xmm4 (blends xmm0 and xmm15 based on xmm4 mask)
    ; Wait, blendvps blends src into dst where mask has sign bit set!
    ; Synax: blendvps xmm0, xmm1, xmm0 (implicit or explicit mask in xmm0 depending on SSE vs AVX).
    ; For SSE4.1, blendvps is: blendvps xmm0, xmm1 (with mask implicitly in xmm0 - wait, no, mask is in xmm0? No, mask is in xmm0, but wait, the instruction blendvps uses xmm0 as the control register. So target = blendvps(dst, src, xmm0)).
    ; Let's write it using simple bitwise logical OR/AND to avoid blendvps syntax differences, which is robust:
    ; mask = (src == INT_MIN)
    ; max_part = mask & INT_MAX
    ; abs_part = ~mask & abs_val
    ; res = max_part | abs_part
    ; Let's reconstruct or keep masks:
    ; we can store the masks in xmm8-xmm11!
    ; Yes!
    ; xmm8 = (xmm0 == INT_MIN)
    ; ...
    ; That is perfectly robust!
    movups  xmm8, xmm0
    movups  xmm9, xmm1
    movups  xmm10, xmm2
    movups  xmm11, xmm3

    pcmpeqd xmm8, xmm14
    pcmpeqd xmm9, xmm14
    pcmpeqd xmm10, xmm14
    pcmpeqd xmm11, xmm14

    pabsd   xmm0, xmm0
    pabsd   xmm1, xmm1
    pabsd   xmm2, xmm2
    pabsd   xmm3, xmm3

    andnps  xmm8, xmm0          ; xmm8 = ~mask & abs(x)
    andnps  xmm9, xmm1
    andnps  xmm10, xmm2
    andnps  xmm11, xmm3

    ; Now recreate masks
    movups  xmm0, [rsi]
    movups  xmm1, [rsi + 16]
    movups  xmm2, [rsi + 32]
    movups  xmm3, [rsi + 48]

    pcmpeqd xmm0, xmm14
    pcmpeqd xmm1, xmm14
    pcmpeqd xmm2, xmm14
    pcmpeqd xmm3, xmm14

    andps   xmm0, xmm15         ; xmm0 = mask & INT32_MAX
    andps   xmm1, xmm15
    andps   xmm2, xmm15
    andps   xmm3, xmm15

    orps    xmm0, xmm8
    orps    xmm1, xmm9
    orps    xmm2, xmm10
    orps    xmm3, xmm11

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

.single_ints:
    cmp     rdx, 4
    jb      .residuals

    mov     rcx, rdx
    shr     rcx, 2

.loop_vector:
    movups  xmm0, [rsi]
    movups  xmm8, xmm0
    pcmpeqd xmm8, xmm14
    pabsd   xmm0, xmm0
    andnps  xmm8, xmm0
    movups  xmm0, [rsi]
    pcmpeqd xmm0, xmm14
    andps   xmm0, xmm15
    orps    xmm0, xmm8
    movups  [rdi], xmm0
    add     rsi, 16
    add     rdi, 16
    dec     rcx
    jnz     .loop_vector

    and     rdx, 3
    jz      .done

.residuals:
    mov     edi, [rsi]
    call    umath_abs_i32_sat
    mov     [rdi], eax
    add     rsi, 4
    add     rdi, 4
    dec     rdx
    jnz     .residuals

.done:
    ret

; -----------------------------------------------------------------------------
; umath_abs_i32_sat_inplace - in-place saturating absolute value for 32-bit int array
; args:    rdi = buffer pointer (buf)
;          rsi = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_abs_i32_sat_inplace
umath_abs_i32_sat_inplace:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done

    mov     rdx, rsi
    mov     rsi, rdi
    call    umath_abs_i32_sat_array
.done:
    ret

; -----------------------------------------------------------------------------
; umath_abs_i32_is_negative - check if 32-bit integer is negative
; args:    edi = input signed 32-bit integer (val)
; returns: eax = 1 (negative) or 0 (non-negative)
; -----------------------------------------------------------------------------
global umath_abs_i32_is_negative
umath_abs_i32_is_negative:
    test    edi, edi
    sets    al
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_abs_i32_sign - get sign of 32-bit integer
; args:    edi = input signed 32-bit integer (val)
; returns: eax = -1 (val < 0), 0 (val == 0), 1 (val > 0)
; -----------------------------------------------------------------------------
global umath_abs_i32_sign
umath_abs_i32_sign:
    xor     eax, eax
    test    edi, edi
    jz      .done               ; zero -> returns 0
    
    mov     eax, 1
    test    edi, edi
    jns     .done               ; positive -> returns 1
    
    mov     eax, -1             ; negative -> returns -1
.done:
    ret

%endif ; GUARD_LIB_UMATH_SCALAR_ABS_I32_ASM
