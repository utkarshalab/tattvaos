%ifndef GUARD_LIB_UMATH_INTEGER_PRIME_ASM
%define GUARD_LIB_UMATH_INTEGER_PRIME_ASM
; =============================================================================
; umath - unified math library
; integer/prime.asm - deterministic primality for u64
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
;   umath_is_prime_u64(n)    eax = 1 if n is prime
;   umath_next_prime_u64(n)  the smallest prime > n, 0 if none fits in u64
;
; is_prime: trial division by the primes up to 37 settles every n below
; 41^2 = 1681 and every multiple of those primes; the rest go through
; Miller-Rabin with the first twelve primes as bases. That base set is
; proven to make the test exact (no strong pseudoprime to all of them)
; for every n below 3.3 * 10^24, so for all 64-bit n -- no probability.
; The modular squarings use one mul + div each (umath_powmod_u64's
; method), so no product can overflow.
; =============================================================================

bits 64

%include "lib/umath/integer/modular.asm"
%include "lib/umath/cpuid/fallback.asm"

section .rodata
align 8
primeu64_small:     dq 2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37
primeu64_count      equ 12

section .text

; -----------------------------------------------------------------------------
; umath_is_prime_u64 - deterministic primality test
; args:    rdi = n
; returns: eax = 1 if n is prime, else 0
; -----------------------------------------------------------------------------
global umath_is_prime_u64
umath_is_prime_u64:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi            ; n
    xor     eax, eax
    cmp     rbx, 2
    jb      .out
    ; trial division by the small primes
    lea     r12, [rel primeu64_small]
    xor     r13d, r13d
.trial:
    mov     rcx, [r12 + r13*8]
    cmp     rbx, rcx
    je      .prime
    mov     rax, rbx
    xor     edx, edx
    div     rcx
    test    rdx, rdx
    jz      .composite
    inc     r13d
    cmp     r13d, primeu64_count
    jb      .trial
    cmp     rbx, 1681
    jb      .prime
    ; n - 1 = d * 2^s, d odd
    lea     r14, [rbx - 1]
    um_tzcnt r15, r14           ; s
    mov     ecx, r15d
    shr     r14, cl             ; d
    xor     r13d, r13d
.base:
    mov     rdi, [r12 + r13*8]
    mov     rsi, r14
    mov     rdx, rbx
    call    umath_powmod_u64    ; x = a^d mod n
    cmp     rax, 1
    je      .next_base
    lea     r8, [rbx - 1]
    cmp     rax, r8
    je      .next_base
    mov     r9, r15
.square:
    dec     r9
    jz      .composite          ; never reached n - 1
    mul     rax
    div     rbx
    mov     rax, rdx            ; x = x^2 mod n
    cmp     rax, r8
    je      .next_base
    cmp     rax, 1
    je      .composite          ; nontrivial square root of 1
    jmp     .square
.next_base:
    inc     r13d
    cmp     r13d, primeu64_count
    jb      .base
.prime:
    mov     eax, 1
    jmp     .out
.composite:
    xor     eax, eax
.out:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; umath_next_prime_u64 - smallest prime greater than n
; args:    rdi = n
; returns: rax = next prime, or 0 if it would exceed 2^64 - 1
;          (n >= 18446744073709551557, the largest 64-bit prime)
; -----------------------------------------------------------------------------
global umath_next_prime_u64
umath_next_prime_u64:
    push    rbx
    mov     eax, 2
    cmp     rdi, 2
    jb      .out
    lea     rbx, [rdi + 1]
    or      rbx, 1              ; first odd candidate above n
    jz      .none               ; wrapped
    cmp     rbx, rdi
    jbe     .none
.try:
    mov     rdi, rbx
    call    umath_is_prime_u64
    test    eax, eax
    jnz     .found
    add     rbx, 2
    jc      .none
    jmp     .try
.found:
    mov     rax, rbx
    jmp     .out
.none:
    xor     eax, eax
.out:
    pop     rbx
    ret

%endif ; GUARD_LIB_UMATH_INTEGER_PRIME_ASM
