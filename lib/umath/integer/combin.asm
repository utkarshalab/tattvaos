%ifndef GUARD_LIB_UMATH_INTEGER_COMBIN_ASM
%define GUARD_LIB_UMATH_INTEGER_COMBIN_ASM
; =============================================================================
; umath - unified math library
; integer/combin.asm - factorials and binomial coefficients on u64
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
;   umath_factorial_u64(n)                 n!, 0 when n > 20 (21! > 2^64)
;   umath_binomial_u64_checked(n, k, *out) eax = 1 and *out = C(n, k) when
;                                          it fits in 64 bits; eax = 0 on
;                                          overflow; C(n, k) = 0 for k > n
;   umath_binomial_u64(n, k)               C(n, k), 0 on overflow
;
; factorial is a table lookup. binomial uses k = min(k, n - k) and the
; recurrence C(m + i, i) = C(m + i - 1, i - 1) * (m + i) / i with m = n - k,
; whose every step is an exact integer. Each step's product is formed in
; 128 bits and divided by i; the quotient is the next (exact) binomial, and
; it overflows exactly when the high half of the product is >= i -- which is
; tested before the division, so `div` never faults. Intermediate values
; are binomials no larger than the result, so no step can overflow unless
; the result does.
; =============================================================================

bits 64

section .rodata
align 8
combinu64_fact:
    dq 1, 1, 2, 6, 24, 120, 720, 5040, 40320, 362880, 3628800, 39916800
    dq 479001600, 6227020800, 87178291200, 1307674368000, 20922789888000
    dq 355687428096000, 6402373705728000, 121645100408832000
    dq 2432902008176640000

section .text

; -----------------------------------------------------------------------------
; umath_factorial_u64 - n!
; args:    rdi = n
; returns: rax = n!, or 0 for n > 20
; -----------------------------------------------------------------------------
global umath_factorial_u64
umath_factorial_u64:
    xor     eax, eax
    cmp     rdi, 20
    ja      .done
    lea     rax, [rel combinu64_fact]
    mov     rax, [rax + rdi*8]
.done:
    ret

; -----------------------------------------------------------------------------
; umath_binomial_u64_checked - C(n, k) with overflow detection
; args:    rdi = n, rsi = k, rdx = u64 *out (may be NULL)
; returns: eax = 1 and *out = C(n, k) if it fits, else eax = 0
; -----------------------------------------------------------------------------
global umath_binomial_u64_checked
umath_binomial_u64_checked:
    mov     r10, rdx            ; out
    xor     r9d, r9d            ; C(n, k) = 0 for k > n
    cmp     rsi, rdi
    ja      .store
    mov     rax, rdi
    sub     rax, rsi            ; n - k
    cmp     rax, rsi
    jae     .small_k
    xchg    rax, rsi            ; k = min(k, n - k)
.small_k:
    mov     r8, rax             ; m = n - k
    mov     r9d, 1              ; C(m, 0)
    mov     ecx, 1              ; i
.loop:
    cmp     rcx, rsi
    ja      .store
    lea     rax, [r8 + rcx]     ; m + i (<= n, no overflow)
    mul     r9                  ; rdx:rax = C * (m + i)
    cmp     rdx, rcx
    jae     .overflow           ; quotient would not fit in 64 bits
    div     rcx
    mov     r9, rax
    inc     rcx
    jmp     .loop
.store:
    test    r10, r10
    jz      .ok
    mov     [r10], r9
.ok:
    mov     eax, 1
    ret
.overflow:
    xor     eax, eax
    ret

; -----------------------------------------------------------------------------
; umath_binomial_u64 - C(n, k), 0 on overflow
; args:    rdi = n, rsi = k
; returns: rax = C(n, k), or 0 if it does not fit (or k > n)
; -----------------------------------------------------------------------------
global umath_binomial_u64
umath_binomial_u64:
    sub     rsp, 8
    mov     qword [rsp], 0
    mov     rdx, rsp
    call    umath_binomial_u64_checked
    mov     rax, [rsp]
    add     rsp, 8
    ret

%endif ; GUARD_LIB_UMATH_INTEGER_COMBIN_ASM
