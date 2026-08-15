%ifndef GUARD_LIB_UMATH_SCALAR_ABS_I64_ASM
%define GUARD_LIB_UMATH_SCALAR_ABS_I64_ASM
; =============================================================================
; umath - unified math library
; scalar/abs_i64.asm - signed 64-bit integer absolute value implementations
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; Concepts:
;   - Branchless 64-bit absolute value uses cqo and xor/sub math.
;   - Saturating absolute value prevents wrapping of INT64_MIN
;     (0x8000000000000000) into itself, mapping it instead to
;     INT64_MAX (0x7FFFFFFFFFFFFFFF).
;   - Vectorized loop utilizing the AVX2 VPABSQ instruction or scalar loops.
;   - Vectorized saturating absolute array mapping.
;   - Counting negative integers in 64-bit array.
; =============================================================================

bits 64
section .text

align 32
absi64_int64_min:    dq 0x8000000000000000, 0x8000000000000000, 0x8000000000000000, 0x8000000000000000
absi64_int64_max:    dq 0x7FFFFFFFFFFFFFFF, 0x7FFFFFFFFFFFFFFF, 0x7FFFFFFFFFFFFFFF, 0x7FFFFFFFFFFFFFFF

; -----------------------------------------------------------------------------
; umath_abs_i64 - scalar branchless 64-bit absolute value
; args:    rdi = input signed 64-bit integer (val)
; returns: rax = absolute value
; -----------------------------------------------------------------------------
global umath_abs_i64
umath_abs_i64:
    mov     rax, rdi
    cqo                         ; rdx = sign bit of rax repeated (0 or -1)
    xor     rax, rdx            ; bitwise complement if negative
    sub     rax, rdx            ; add 1 if negative (sub -1) to complete two's complement
    ret

; -----------------------------------------------------------------------------
; umath_abs_i64_sat - scalar saturating 64-bit absolute value
; args:    rdi = input signed 64-bit integer (val)
; returns: rax = saturating absolute value (clamps INT64_MIN to INT64_MAX)
; -----------------------------------------------------------------------------
global umath_abs_i64_sat
umath_abs_i64_sat:
    movabs  r8, 0x8000000000000000
    cmp     rdi, r8             ; check if val == INT64_MIN
    je      .clamp

    mov     rax, rdi
    cqo
    xor     rax, rdx
    sub     rax, rdx
    ret

.clamp:
    movabs  rax, 0x7FFFFFFFFFFFFFFF ; return INT64_MAX
    ret

; -----------------------------------------------------------------------------
; umath_abs_i64_array - compute absolute value for an array of 64-bit integers
; args:    rdi = destination pointer (dst)
;          rsi = source pointer (src)
;          rdx = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_abs_i64_array
umath_abs_i64_array:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done
    test    rdx, rdx
    jz      .done

    cmp     rdx, 8
    jb      .single_ints

    mov     rcx, rdx
    shr     rcx, 3              ; count of 8-integer (64-byte) blocks

.loop_unrolled:
    vmovdqu ymm0, [rsi]
    vmovdqu ymm1, [rsi + 32]

    vpabsq  ymm0, ymm0
    vpabsq  ymm1, ymm1

    vmovdqu [rdi], ymm0
    vmovdqu [rdi + 32], ymm1

    add     rsi, 64
    add     rdi, 64
    dec     rcx
    jnz     .loop_unrolled

    and     rdx, 7
    jz      .done

.single_ints:
    cmp     rdx, 2
    jb      .residuals

    mov     rcx, rdx
    shr     rcx, 1              ; count of 2-integer vectors

.loop_vector:
    vmovdqu xmm0, [rsi]
    vpabsq  xmm0, xmm0
    vmovdqu [rdi], xmm0
    add     rsi, 16
    add     rdi, 16
    dec     rcx
    jnz     .loop_vector

    and     rdx, 1
    jz      .done

.residuals:
    mov     rax, [rsi]
    cqo
    xor     rax, rdx
    sub     rax, rdx
    mov     [rdi], rax
    add     rsi, 8
    add     rdi, 8
    dec     rdx
    jnz     .residuals

.done:
    vzeroupper
    ret

; -----------------------------------------------------------------------------
; umath_abs_i64_inplace - in-place absolute value for 64-bit integers
; args:    rdi = buffer pointer (buf)
;          rsi = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_abs_i64_inplace
umath_abs_i64_inplace:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done

    cmp     rsi, 8
    jb      .single_ints

    mov     rcx, rsi
    shr     rcx, 3

.loop_unrolled:
    vmovdqu ymm0, [rdi]
    vmovdqu ymm1, [rdi + 32]

    vpabsq  ymm0, ymm0
    vpabsq  ymm1, ymm1

    vmovdqu [rdi], ymm0
    vmovdqu [rdi + 32], ymm1

    add     rdi, 64
    dec     rcx
    jnz     .loop_unrolled

    and     rsi, 7
    jz      .done

.single_ints:
    cmp     rsi, 2
    jb      .residuals

    mov     rcx, rsi
    shr     rcx, 1

.loop_vector:
    vmovdqu xmm0, [rdi]
    vpabsq  xmm0, xmm0
    vmovdqu [rdi], xmm0
    add     rdi, 16
    dec     rcx
    jnz     .loop_vector

    and     rsi, 1
    jz      .done

.residuals:
    mov     rax, [rdi]
    cqo
    xor     rax, rdx
    sub     rax, rdx
    mov     [rdi], rax
    add     rdi, 8
    dec     rsi
    jnz     .residuals

.done:
    vzeroupper
    ret

; -----------------------------------------------------------------------------
; umath_abs_i64_sat_array - compute saturating absolute value for 64-bit int array
; args:    rdi = destination pointer (dst)
;          rsi = source pointer (src)
;          rdx = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_abs_i64_sat_array
umath_abs_i64_sat_array:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done
    test    rdx, rdx
    jz      .done

    vmovdqu ymm14, [rel absi64_int64_min]
    vmovdqu ymm15, [rel absi64_int64_max]

    cmp     rdx, 8
    jb      .single_ints

    mov     rcx, rdx
    shr     rcx, 3

.loop_unrolled:
    vmovdqu ymm0, [rsi]         ; ymm0 = original 4 elements
    vmovdqu ymm1, [rsi + 32]    ; ymm1 = original next 4 elements

    ; ymm2 = mask (elements == INT64_MIN)
    ; ymm3 = mask next
    vmovdqu ymm2, ymm0
    vmovdqu ymm3, ymm1
    vpcmpeqq ymm2, ymm2, ymm14
    vpcmpeqq ymm3, ymm3, ymm14

    vpabsq  ymm0, ymm0          ; absolute value
    vpabsq  ymm1, ymm1

    ; res = (abs_val & ~mask) | (INT64_MAX & mask)
    vpandn  ymm2, ymm2, ymm0
    vpandn  ymm3, ymm3, ymm1

    ; reload mask to blend the max value part
    vmovdqu ymm0, [rsi]
    vmovdqu ymm1, [rsi + 32]
    vpcmpeqq ymm0, ymm0, ymm14
    vpcmpeqq ymm1, ymm1, ymm14

    vpand   ymm0, ymm0, ymm15
    vpand   ymm1, ymm1, ymm15

    vpor    ymm0, ymm0, ymm2
    vpor    ymm1, ymm1, ymm3

    vmovdqu [rdi], ymm0
    vmovdqu [rdi + 32], ymm1

    add     rsi, 64
    add     rdi, 64
    dec     rcx
    jnz     .loop_unrolled

    and     rdx, 7
    jz      .done

.single_ints:
    cmp     rdx, 2
    jb      .residuals

    mov     rcx, rdx
    shr     rcx, 1

.loop_vector:
    vmovdqu xmm0, [rsi]
    vmovdqu xmm2, xmm0
    vpcmpeqq xmm2, xmm2, xmm14
    vpabsq  xmm0, xmm0
    vpandn  xmm2, xmm2, xmm0
    
    vmovdqu xmm0, [rsi]
    vpcmpeqq xmm0, xmm0, xmm14
    vpand   xmm0, xmm0, xmm15
    vpor    xmm0, xmm0, xmm2
    vmovdqu [rdi], xmm0
    add     rsi, 16
    add     rdi, 16
    dec     rcx
    jnz     .loop_vector

    and     rdx, 1
    jz      .done

.residuals:
    mov     r8, [rsi]
    call    umath_abs_i64_sat_helper
    mov     [rdi], rax
    add     rsi, 8
    add     rdi, 8
    dec     rdx
    jnz     .residuals

.done:
    vzeroupper
    ret

; Helper to avoid stack frame inside absolute residual path
umath_abs_i64_sat_helper:
    movabs  r9, 0x8000000000000000
    cmp     r8, r9
    je      .clamp_h
    mov     rax, r8
    cqo
    xor     rax, rdx
    sub     rax, rdx
    ret
.clamp_h:
    movabs  rax, 0x7FFFFFFFFFFFFFFF
    ret

; -----------------------------------------------------------------------------
; umath_abs_i64_sat_inplace - in-place saturating absolute value for 64-bit int array
; args:    rdi = buffer pointer (buf)
;          rsi = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_abs_i64_sat_inplace
umath_abs_i64_sat_inplace:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done

    mov     rdx, rsi
    mov     rsi, rdi
    call    umath_abs_i64_sat_array
.done:
    ret

; -----------------------------------------------------------------------------
; umath_abs_i64_count_negative - count negative elements in 64-bit int array
; args:    rdi = source pointer (src)
;          rsi = size of array (count)
; returns: rax = count of negative elements
; -----------------------------------------------------------------------------
global umath_abs_i64_count_negative
umath_abs_i64_count_negative:
    xor     rax, rax
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done

.loop:
    mov     rdx, [rdi]
    test    rdx, rdx
    jns     .next
    inc     rax
.next:
    add     rdi, 8
    dec     rsi
    jnz     .loop

.done:
    ret

; -----------------------------------------------------------------------------
; umath_abs_i64_is_negative - check if 64-bit integer is negative
; args:    rdi = input signed 64-bit integer (val)
; returns: rax = 1 (negative) or 0 (non-negative)
; -----------------------------------------------------------------------------
global umath_abs_i64_is_negative
umath_abs_i64_is_negative:
    test    rdi, rdi
    sets    al
    movzx   rax, al
    ret

; -----------------------------------------------------------------------------
; umath_abs_i64_sign - get sign of 64-bit integer
; args:    rdi = input signed 64-bit integer (val)
; returns: rax = -1 (val < 0), 0 (val == 0), 1 (val > 0)
; -----------------------------------------------------------------------------
global umath_abs_i64_sign
umath_abs_i64_sign:
    xor     rax, rax
    test    rdi, rdi
    jz      .done               ; zero -> returns 0
    
    mov     rax, 1
    test    rdi, rdi
    jns     .done               ; positive -> returns 1
    
    mov     rax, -1             ; negative -> returns -1
.done:
    ret

%endif ; GUARD_LIB_UMATH_SCALAR_ABS_I64_ASM
