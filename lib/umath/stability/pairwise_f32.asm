%ifndef GUARD_LIB_UMATH_STABILITY_PAIRWISE_F32_ASM
%define GUARD_LIB_UMATH_STABILITY_PAIRWISE_F32_ASM
; =============================================================================
; umath - unified math library
; stability/pairwise_f32.asm - pairwise (cascade) summation, single precision
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; Same scheme as pairwise_f64.asm, entirely in float: leaf blocks of 256
; elements summed with sixteen lanes (four xmm accumulators, 16 floats per
; iteration, at most 16 terms per lane), then combined like a binary counter
; over a 64-slot partial array. Error grows with log2(n), not n. For a
; float result within an ULP of the exact sum, use umath_kahan_sum_f32
; (double accumulation) instead.
;
; NaN and Inf propagate like ordinary addition.
; =============================================================================

bits 64

PAIRWISEF32_LEAF equ 256        ; elements per leaf block

section .text

; -----------------------------------------------------------------------------
; pairwisef32__leaf - internal: sum of 1..PAIRWISEF32_LEAF floats
; args:    rdi = source pointer, rsi = count
; returns: xmm0 = sum
; Clobbers rcx, rsi, rdi, xmm1-xmm7. Not declared global.
; -----------------------------------------------------------------------------
pairwisef32__leaf:
    xorps   xmm0, xmm0
    xorps   xmm1, xmm1
    xorps   xmm2, xmm2
    xorps   xmm3, xmm3
    mov     rcx, rsi
    shr     rcx, 4              ; count of 16-float groups
    jz      .combine
.loop16:
    movups  xmm4, [rdi]
    movups  xmm5, [rdi + 16]
    movups  xmm6, [rdi + 32]
    movups  xmm7, [rdi + 48]
    addps   xmm0, xmm4
    addps   xmm1, xmm5
    addps   xmm2, xmm6
    addps   xmm3, xmm7
    add     rdi, 64
    dec     rcx
    jnz     .loop16
.combine:
    addps   xmm0, xmm1          ; pairwise across the four accumulators
    addps   xmm2, xmm3
    addps   xmm0, xmm2
    movhlps xmm1, xmm0
    addps   xmm0, xmm1          ; lanes {0+2, 1+3}
    movaps  xmm1, xmm0
    shufps  xmm1, xmm1, 0x55
    addss   xmm0, xmm1          ; lane 0 + lane 1
    and     rsi, 15
    jz      .done
.tail:
    addss   xmm0, [rdi]
    add     rdi, 4
    dec     rsi
    jnz     .tail
.done:
    ret

; -----------------------------------------------------------------------------
; umath_pairwise_sum_f32 - pairwise sum of an array of floats
; args:    rdi = source pointer (src)
;          rsi = size of array (count)
; returns: xmm0 = sum (0.0f for an empty or NULL array)
; -----------------------------------------------------------------------------
global umath_pairwise_sum_f32
umath_pairwise_sum_f32:
    xorps   xmm0, xmm0
    test    rdi, rdi
    jz      .empty
    test    rsi, rsi
    jz      .empty

    push    rbx
    push    r12
    push    r13
    sub     rsp, 64 * 4         ; partial sums per level; keeps rsp 16-aligned
    mov     rbx, rdi            ; next element
    mov     r12, rsi            ; elements left
    xor     r13d, r13d          ; bit k set = level k holds a partial sum

.next_leaf:
    mov     rsi, PAIRWISEF32_LEAF
    cmp     r12, rsi
    cmovb   rsi, r12            ; this leaf's length
    mov     rdi, rbx
    lea     rbx, [rbx + rsi * 4]
    sub     r12, rsi
    call    pairwisef32__leaf   ; xmm0 = leaf sum

    xor     ecx, ecx
.carry:
    bt      r13, rcx
    jnc     .place
    addss   xmm0, [rsp + rcx * 4] ; merge equal-sized partials
    btr     r13, rcx
    inc     ecx
    jmp     .carry
.place:
    movss   [rsp + rcx * 4], xmm0
    bts     r13, rcx
    test    r12, r12
    jnz     .next_leaf

    ; fold the remaining levels, smallest partials first
    xorps   xmm0, xmm0
.fold:
    test    r13, r13
    jz      .out
    bsf     rcx, r13
    addss   xmm0, [rsp + rcx * 4]
    btr     r13, rcx
    jmp     .fold
.out:
    add     rsp, 64 * 4
    pop     r13
    pop     r12
    pop     rbx
.empty:
    ret

%endif ; GUARD_LIB_UMATH_STABILITY_PAIRWISE_F32_ASM
