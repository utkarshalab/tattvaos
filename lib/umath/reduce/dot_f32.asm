%ifndef GUARD_LIB_UMATH_REDUCE_DOT_F32_ASM
%define GUARD_LIB_UMATH_REDUCE_DOT_F32_ASM
; =============================================================================
; umath - unified math library
; reduce/dot_f32.asm - dot product and sum of squares, single precision
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; Same cascade as dot_f64.asm in float throughout: leaf blocks of 256 pairs
; accumulated in sixteen lanes (mulps + addps, at most 16 products per
; lane), leaves merged like a binary counter. Error grows with log2(n);
; each product is rounded to float before it is added.
;
; NaN and Inf propagate like ordinary arithmetic (0 * Inf = NaN).
; =============================================================================

bits 64

REDDOTF32_LEAF equ 256          ; element pairs per leaf block

section .text

; -----------------------------------------------------------------------------
; reddotf32__leaf - internal: dot product of 1..REDDOTF32_LEAF float pairs
; args:    rdi = a, rsi = b, rdx = count
; returns: xmm0 = sum of a[i] * b[i]
; Clobbers rcx, rdx, rsi, rdi, xmm1-xmm7. Not declared global.
; -----------------------------------------------------------------------------
reddotf32__leaf:
    xorps   xmm0, xmm0
    xorps   xmm1, xmm1
    xorps   xmm2, xmm2
    xorps   xmm3, xmm3
    mov     rcx, rdx
    shr     rcx, 4              ; count of 16-pair groups
    jz      .combine
.loop16:
    movups  xmm4, [rdi]
    movups  xmm5, [rsi]
    mulps   xmm4, xmm5
    addps   xmm0, xmm4
    movups  xmm6, [rdi + 16]
    movups  xmm7, [rsi + 16]
    mulps   xmm6, xmm7
    addps   xmm1, xmm6
    movups  xmm4, [rdi + 32]
    movups  xmm5, [rsi + 32]
    mulps   xmm4, xmm5
    addps   xmm2, xmm4
    movups  xmm6, [rdi + 48]
    movups  xmm7, [rsi + 48]
    mulps   xmm6, xmm7
    addps   xmm3, xmm6
    add     rdi, 64
    add     rsi, 64
    dec     rcx
    jnz     .loop16
.combine:
    addps   xmm0, xmm1
    addps   xmm2, xmm3
    addps   xmm0, xmm2
    movhlps xmm1, xmm0
    addps   xmm0, xmm1
    movaps  xmm1, xmm0
    shufps  xmm1, xmm1, 0x55
    addss   xmm0, xmm1
    and     rdx, 15
    jz      .done
.tail:
    movss   xmm1, [rdi]
    mulss   xmm1, [rsi]
    addss   xmm0, xmm1
    add     rdi, 4
    add     rsi, 4
    dec     rdx
    jnz     .tail
.done:
    ret

; -----------------------------------------------------------------------------
; umath_reduce_dot_f32 - dot product of two float arrays
; args:    rdi = pointer to a
;          rsi = pointer to b
;          rdx = size of arrays (count)
; returns: xmm0 = sum of a[i] * b[i] (0.0f for empty or NULL input)
; -----------------------------------------------------------------------------
global umath_reduce_dot_f32
umath_reduce_dot_f32:
    xorps   xmm0, xmm0
    test    rdi, rdi
    jz      .empty
    test    rsi, rsi
    jz      .empty
    test    rdx, rdx
    jz      .empty

    push    rbx
    push    r12
    push    r13
    push    r14
    sub     rsp, 64 * 4 + 8     ; partial sums per level; rsp 16-aligned at calls
    mov     rbx, rdi            ; next a
    mov     r14, rsi            ; next b
    mov     r12, rdx            ; pairs left
    xor     r13d, r13d          ; bit k set = level k holds a partial sum

.next_leaf:
    mov     rdx, REDDOTF32_LEAF
    cmp     r12, rdx
    cmovb   rdx, r12
    mov     rdi, rbx
    mov     rsi, r14
    lea     rbx, [rbx + rdx * 4]
    lea     r14, [r14 + rdx * 4]
    sub     r12, rdx
    call    reddotf32__leaf

    xor     ecx, ecx
.carry:
    bt      r13, rcx
    jnc     .place
    addss   xmm0, [rsp + rcx * 4]
    btr     r13, rcx
    inc     ecx
    jmp     .carry
.place:
    movss   [rsp + rcx * 4], xmm0
    bts     r13, rcx
    test    r12, r12
    jnz     .next_leaf

    xorps   xmm0, xmm0
.fold:
    test    r13, r13
    jz      .out
    bsf     rcx, r13
    addss   xmm0, [rsp + rcx * 4]
    btr     r13, rcx
    jmp     .fold
.out:
    add     rsp, 64 * 4 + 8
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
.empty:
    ret

; -----------------------------------------------------------------------------
; umath_reduce_sumsq_f32 - sum of squares of a float array
; args:    rdi = source pointer (src)
;          rsi = size of array (count)
; returns: xmm0 = sum of src[i]^2 (0.0f for an empty or NULL array)
; -----------------------------------------------------------------------------
global umath_reduce_sumsq_f32
umath_reduce_sumsq_f32:
    mov     rdx, rsi
    mov     rsi, rdi
    jmp     umath_reduce_dot_f32

%endif ; GUARD_LIB_UMATH_REDUCE_DOT_F32_ASM
