%ifndef GUARD_LIB_UMATH_REDUCE_DOT_F64_ASM
%define GUARD_LIB_UMATH_REDUCE_DOT_F64_ASM
; =============================================================================
; umath - unified math library
; reduce/dot_f64.asm - dot product and sum of squares, double precision
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; Same cascade as stability/pairwise_f64.asm, applied to products: leaf
; blocks of 256 element pairs are accumulated in eight SIMD lanes
; (mulpd + addpd, at most 32 products per lane), and leaf results are merged
; like a binary counter over a 64-slot partial array. The error grows with
; log2(n) instead of n. Each product is rounded once before it is added
; (no FMA, which the baseline target does not guarantee).
;
; umath_reduce_sumsq_f64(x) is dot(x, x): the core of the L2 norm and of
; variance-style reductions.
;
; NaN and Inf propagate like ordinary arithmetic (0 * Inf = NaN).
; =============================================================================

bits 64

REDDOTF64_LEAF equ 256          ; element pairs per leaf block

section .text

; -----------------------------------------------------------------------------
; reddotf64__leaf - internal: dot product of 1..REDDOTF64_LEAF element pairs
; args:    rdi = a, rsi = b, rdx = count
; returns: xmm0 = sum of a[i] * b[i]
; Clobbers rcx, rdx, rsi, rdi, xmm1-xmm7. Not declared global.
; -----------------------------------------------------------------------------
reddotf64__leaf:
    xorpd   xmm0, xmm0
    xorpd   xmm1, xmm1
    xorpd   xmm2, xmm2
    xorpd   xmm3, xmm3
    mov     rcx, rdx
    shr     rcx, 3              ; count of 8-pair groups
    jz      .combine
.loop8:
    movupd  xmm4, [rdi]
    movupd  xmm5, [rsi]
    mulpd   xmm4, xmm5
    addpd   xmm0, xmm4
    movupd  xmm6, [rdi + 16]
    movupd  xmm7, [rsi + 16]
    mulpd   xmm6, xmm7
    addpd   xmm1, xmm6
    movupd  xmm4, [rdi + 32]
    movupd  xmm5, [rsi + 32]
    mulpd   xmm4, xmm5
    addpd   xmm2, xmm4
    movupd  xmm6, [rdi + 48]
    movupd  xmm7, [rsi + 48]
    mulpd   xmm6, xmm7
    addpd   xmm3, xmm6
    add     rdi, 64
    add     rsi, 64
    dec     rcx
    jnz     .loop8
.combine:
    addpd   xmm0, xmm1
    addpd   xmm2, xmm3
    addpd   xmm0, xmm2
    movapd  xmm1, xmm0
    unpckhpd xmm1, xmm1
    addsd   xmm0, xmm1
    and     rdx, 7
    jz      .done
.tail:
    movsd   xmm1, [rdi]
    mulsd   xmm1, [rsi]
    addsd   xmm0, xmm1
    add     rdi, 8
    add     rsi, 8
    dec     rdx
    jnz     .tail
.done:
    ret

; -----------------------------------------------------------------------------
; umath_reduce_dot_f64 - dot product of two double arrays
; args:    rdi = pointer to a
;          rsi = pointer to b
;          rdx = size of arrays (count)
; returns: xmm0 = sum of a[i] * b[i] (0.0 for empty or NULL input)
; -----------------------------------------------------------------------------
global umath_reduce_dot_f64
umath_reduce_dot_f64:
    xorpd   xmm0, xmm0
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
    sub     rsp, 64 * 8 + 8     ; partial sums per level; rsp 16-aligned at calls
    mov     rbx, rdi            ; next a
    mov     r14, rsi            ; next b
    mov     r12, rdx            ; pairs left
    xor     r13d, r13d          ; bit k set = level k holds a partial sum

.next_leaf:
    mov     rdx, REDDOTF64_LEAF
    cmp     r12, rdx
    cmovb   rdx, r12            ; this leaf's length
    mov     rdi, rbx
    mov     rsi, r14
    lea     rbx, [rbx + rdx * 8]
    lea     r14, [r14 + rdx * 8]
    sub     r12, rdx
    call    reddotf64__leaf     ; xmm0 = leaf dot product

    xor     ecx, ecx
.carry:
    bt      r13, rcx
    jnc     .place
    addsd   xmm0, [rsp + rcx * 8] ; merge equal-sized partials
    btr     r13, rcx
    inc     ecx
    jmp     .carry
.place:
    movsd   [rsp + rcx * 8], xmm0
    bts     r13, rcx
    test    r12, r12
    jnz     .next_leaf

    xorpd   xmm0, xmm0          ; fold the levels, smallest partials first
.fold:
    test    r13, r13
    jz      .out
    bsf     rcx, r13
    addsd   xmm0, [rsp + rcx * 8]
    btr     r13, rcx
    jmp     .fold
.out:
    add     rsp, 64 * 8 + 8
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
.empty:
    ret

; -----------------------------------------------------------------------------
; umath_reduce_sumsq_f64 - sum of squares of a double array
; args:    rdi = source pointer (src)
;          rsi = size of array (count)
; returns: xmm0 = sum of src[i]^2 (0.0 for an empty or NULL array)
; -----------------------------------------------------------------------------
global umath_reduce_sumsq_f64
umath_reduce_sumsq_f64:
    mov     rdx, rsi
    mov     rsi, rdi
    jmp     umath_reduce_dot_f64

%endif ; GUARD_LIB_UMATH_REDUCE_DOT_F64_ASM
