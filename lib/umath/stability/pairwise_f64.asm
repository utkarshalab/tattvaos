%ifndef GUARD_LIB_UMATH_STABILITY_PAIRWISE_F64_ASM
%define GUARD_LIB_UMATH_STABILITY_PAIRWISE_F64_ASM
; =============================================================================
; umath - unified math library
; stability/pairwise_f64.asm - pairwise (cascade) summation, double precision
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; Algorithm: the array is cut into leaf blocks of 256 elements. Each leaf is
; summed directly with eight independent lanes (four xmm accumulators, 8
; doubles per iteration), so every lane adds at most 32 terms. Leaf sums are
; then combined like a binary counter: level k of a 64-slot partial array
; holds the sum of 2^k leaves, and a new leaf carries upward until it finds
; an empty level. This is pairwise summation without recursion; the
; rounding error grows with log2(n) instead of n, at the cost of almost
; nothing over a plain vectorized loop.
;
; Use this when "much better than naive, nearly free" is enough; use
; kahan_f64.asm when the result must be within a couple of ULP regardless
; of n or cancellation.
;
; NaN and Inf propagate like ordinary addition.
; =============================================================================

bits 64

PAIRWISEF64_LEAF equ 256        ; elements per leaf block

section .text

; -----------------------------------------------------------------------------
; pairwisef64__leaf - internal: sum of 1..PAIRWISEF64_LEAF doubles
; args:    rdi = source pointer, rsi = count
; returns: xmm0 = sum
; Clobbers rcx, rsi, rdi, xmm1-xmm7. Not declared global.
; -----------------------------------------------------------------------------
pairwisef64__leaf:
    xorpd   xmm0, xmm0
    xorpd   xmm1, xmm1
    xorpd   xmm2, xmm2
    xorpd   xmm3, xmm3
    mov     rcx, rsi
    shr     rcx, 3              ; count of 8-double groups
    jz      .combine
.loop8:
    movupd  xmm4, [rdi]
    movupd  xmm5, [rdi + 16]
    movupd  xmm6, [rdi + 32]
    movupd  xmm7, [rdi + 48]
    addpd   xmm0, xmm4
    addpd   xmm1, xmm5
    addpd   xmm2, xmm6
    addpd   xmm3, xmm7
    add     rdi, 64
    dec     rcx
    jnz     .loop8
.combine:
    addpd   xmm0, xmm1          ; pairwise across the four accumulators
    addpd   xmm2, xmm3
    addpd   xmm0, xmm2
    movapd  xmm1, xmm0
    unpckhpd xmm1, xmm1
    addsd   xmm0, xmm1          ; lane 0 + lane 1
    and     rsi, 7
    jz      .done
.tail:
    addsd   xmm0, [rdi]
    add     rdi, 8
    dec     rsi
    jnz     .tail
.done:
    ret

; -----------------------------------------------------------------------------
; umath_pairwise_sum_f64 - pairwise sum of an array of doubles
; args:    rdi = source pointer (src)
;          rsi = size of array (count)
; returns: xmm0 = sum (0.0 for an empty or NULL array)
; -----------------------------------------------------------------------------
global umath_pairwise_sum_f64
umath_pairwise_sum_f64:
    xorpd   xmm0, xmm0
    test    rdi, rdi
    jz      .empty
    test    rsi, rsi
    jz      .empty

    push    rbx
    push    r12
    push    r13
    sub     rsp, 64 * 8         ; partial sums per level; keeps rsp 16-aligned
    mov     rbx, rdi            ; next element
    mov     r12, rsi            ; elements left
    xor     r13d, r13d          ; bit k set = level k holds a partial sum

.next_leaf:
    mov     rsi, PAIRWISEF64_LEAF
    cmp     r12, rsi
    cmovb   rsi, r12            ; this leaf's length
    mov     rdi, rbx
    lea     rbx, [rbx + rsi * 8]
    sub     r12, rsi
    call    pairwisef64__leaf   ; xmm0 = leaf sum

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

    ; fold the remaining levels, smallest partials first
    xorpd   xmm0, xmm0
.fold:
    test    r13, r13
    jz      .out
    bsf     rcx, r13
    addsd   xmm0, [rsp + rcx * 8]
    btr     r13, rcx
    jmp     .fold
.out:
    add     rsp, 64 * 8
    pop     r13
    pop     r12
    pop     rbx
.empty:
    ret

%endif ; GUARD_LIB_UMATH_STABILITY_PAIRWISE_F64_ASM
