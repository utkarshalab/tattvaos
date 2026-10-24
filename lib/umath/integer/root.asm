%ifndef GUARD_LIB_UMATH_INTEGER_ROOT_ASM
%define GUARD_LIB_UMATH_INTEGER_ROOT_ASM
; =============================================================================
; umath - unified math library
; integer/root.asm - exact integer roots and logarithms of u64
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
;   umath_isqrt_u64(n)      floor(sqrt(n))
;   umath_icbrt_u64(n)      floor(cbrt(n))
;   umath_is_square_u64(n)  eax = 1 if n is a perfect square
;   umath_ilog2_u64(n)      eax = floor(log2(n)), -1 for n = 0
;   umath_ilog10_u64(n)     eax = floor(log10(n)), -1 for n = 0
;
; The roots start from a floating-point estimate (sqrtsd, umath_cbrt_f64),
; which is within one of the answer, then correct it exactly with integer
; arithmetic: the candidate's square/cube is formed as a 128-bit product
; (so it cannot overflow) and compared with n, stepping down while it is
; too big and up while the next one still fits. The result is therefore
; exact for every u64, including values above 2^53 where the double
; estimate itself is rounded. ilog10 uses ilog2 * 1233 / 4096 (log10(2)
; to 12 bits, never too small and at most one too big) and one table
; comparison.
; =============================================================================

bits 64

%include "lib/umath/math_fn/cbrt_f64.asm"

section .rodata
align 8
irootu64_pow10:
    dq 1, 10, 100, 1000, 10000, 100000, 1000000, 10000000, 100000000
    dq 1000000000, 10000000000, 100000000000, 1000000000000
    dq 10000000000000, 100000000000000, 1000000000000000
    dq 10000000000000000, 100000000000000000, 1000000000000000000
    dq 10000000000000000000

section .text

; -----------------------------------------------------------------------------
; irootu64__to_double - internal: rax (u64) -> xmm0, rounded to nearest
; Clobbers rcx.
; -----------------------------------------------------------------------------
irootu64__to_double:
    test    rax, rax
    js      .big
    cvtsi2sd xmm0, rax
    ret
.big:
    mov     rcx, rax
    shr     rcx, 1
    and     eax, 1
    or      rcx, rax            ; halve, keeping the sticky low bit
    cvtsi2sd xmm0, rcx
    addsd   xmm0, xmm0
    ret

; -----------------------------------------------------------------------------
; irootu64__pow - internal: r^k as 128 bits, k = 2 or 3
; args:    r8 = r, r9 = k
; returns: CF = 1 if r^k > 2^64 - 1, else rax = r^k (CF = 0)
; Clobbers rdx.
; -----------------------------------------------------------------------------
irootu64__pow:
    mov     rax, r8
    mul     r8
    test    rdx, rdx
    jnz     .over
    cmp     r9, 2
    je      .fits
    mul     r8
    test    rdx, rdx
    jnz     .over
.fits:
    clc
    ret
.over:
    stc
    ret

; -----------------------------------------------------------------------------
; irootu64__fix - internal: correct the estimate r8 to floor(n^(1/k))
; args:    r8 = estimate, r9 = k, rdi = n
; returns: rax = exact root
; -----------------------------------------------------------------------------
irootu64__fix:
.down:
    call    irootu64__pow
    jc      .dec
    cmp     rax, rdi
    jbe     .up
.dec:
    dec     r8
    jmp     .down
.up:
    inc     r8
    call    irootu64__pow
    jc      .back
    cmp     rax, rdi
    jbe     .up
.back:
    dec     r8
    mov     rax, r8
    ret

; -----------------------------------------------------------------------------
; umath_isqrt_u64 - floor(sqrt(n))
; args:    rdi = n
; returns: rax = floor(sqrt(n))
; -----------------------------------------------------------------------------
global umath_isqrt_u64
umath_isqrt_u64:
    mov     rax, rdi
    cmp     rdi, 2
    jb      .done
    call    irootu64__to_double
    sqrtsd  xmm0, xmm0
    cvttsd2si r8, xmm0          ; <= 2^32
    mov     r9d, 2
    call    irootu64__fix
.done:
    ret

; -----------------------------------------------------------------------------
; umath_icbrt_u64 - floor(cbrt(n))
; args:    rdi = n
; returns: rax = floor(cbrt(n))
; -----------------------------------------------------------------------------
global umath_icbrt_u64
umath_icbrt_u64:
    mov     rax, rdi
    cmp     rdi, 2
    jb      .done
    push    rdi
    call    irootu64__to_double
    call    umath_cbrt_f64
    pop     rdi
    cvttsd2si r8, xmm0          ; <= 2642246
    mov     r9d, 3
    call    irootu64__fix
.done:
    ret

; -----------------------------------------------------------------------------
; umath_is_square_u64 - is n a perfect square?
; args:    rdi = n
; returns: eax = 1 if n = r*r for some integer r, else 0
; -----------------------------------------------------------------------------
global umath_is_square_u64
umath_is_square_u64:
    call    umath_isqrt_u64
    imul    rax, rax            ; < 2^64: r <= 2^32 - 1
    cmp     rax, rdi
    sete    al
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_ilog2_u64 - floor(log2(n))
; args:    rdi = n
; returns: eax = index of the highest set bit, -1 for n = 0
; -----------------------------------------------------------------------------
global umath_ilog2_u64
umath_ilog2_u64:
    mov     eax, -1
    bsr     rcx, rdi
    cmovnz  eax, ecx
    ret

; -----------------------------------------------------------------------------
; umath_ilog10_u64 - floor(log10(n))
; args:    rdi = n
; returns: eax = number of decimal digits - 1, -1 for n = 0
; -----------------------------------------------------------------------------
global umath_ilog10_u64
umath_ilog10_u64:
    mov     eax, -1
    bsr     rcx, rdi
    jz      .done
    lea     eax, [rcx + 1]
    imul    eax, eax, 1233
    shr     eax, 12             ; t, never below the answer, at most 1 over
    lea     rcx, [rel irootu64_pow10]
    cmp     rdi, [rcx + rax*8]
    sbb     eax, 0              ; n < 10^t: t - 1
.done:
    ret

%endif ; GUARD_LIB_UMATH_INTEGER_ROOT_ASM
