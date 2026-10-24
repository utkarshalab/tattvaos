%ifndef GUARD_LIB_UMATH_INTEGER_GCD_ASM
%define GUARD_LIB_UMATH_INTEGER_GCD_ASM
; =============================================================================
; umath - unified math library
; integer/gcd.asm - greatest common divisor, least common multiple, Bezout
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
;   umath_gcd_u64(a, b)                gcd, with gcd(0, 0) = 0
;   umath_gcd_i64(a, b)                gcd(|a|, |b|) as u64 (so INT64_MIN is
;                                      fine: gcd(INT64_MIN, 0) = 2^63)
;   umath_lcm_u64(a, b)                lcm, 0 if either is 0 or the result
;                                      does not fit in 64 bits
;   umath_lcm_u64_checked(a, b, *out)  eax = 1 and *out = lcm when it fits,
;                                      eax = 0 on overflow (*out untouched)
;   umath_egcd_i64(a, b, *x, *y)       g = gcd(|a|, |b|) and Bezout
;                                      coefficients with a*x + b*y = g
;
; gcd is binary (Stein): strip the common power of two once with tzcnt,
; then subtract-and-shift on odd values -- no division at all. lcm is
; a / gcd * b with the multiply checked (64x64 -> 128 bit, overflow when
; the high half is nonzero). egcd is the extended Euclidean algorithm on
; the magnitudes; its coefficients are bounded by max(|a|, |b|) / (2g) + 1,
; so they never overflow, and are then signed for the signs of a and b.
; For a = b = 0 egcd returns g = 0 with x = y = 0.
; =============================================================================

bits 64

%include "lib/umath/cpuid/fallback.asm"

section .text

; -----------------------------------------------------------------------------
; umath_gcd_u64 - binary gcd
; args:    rdi = a, rsi = b
; returns: rax = gcd(a, b)
; -----------------------------------------------------------------------------
global umath_gcd_u64
umath_gcd_u64:
    mov     rax, rsi
    test    rdi, rdi
    jz      .done               ; gcd(0, b) = b
    mov     rax, rdi
    test    rsi, rsi
    jz      .done               ; gcd(a, 0) = a
    mov     r8, rdi
    or      r8, rsi
    um_tzcnt r8, r8             ; k = common power of two
    um_tzcnt rcx, rdi
    shr     rdi, cl             ; a odd
.loop:
    um_tzcnt rcx, rsi
    shr     rsi, cl             ; b odd
    cmp     rdi, rsi
    jbe     .ordered
    xchg    rdi, rsi
.ordered:
    sub     rsi, rdi            ; b - a: even, or zero when done
    jnz     .loop
    mov     rax, rdi
    mov     ecx, r8d
    shl     rax, cl             ; restore 2^k
.done:
    ret

; -----------------------------------------------------------------------------
; umath_gcd_i64 - gcd of signed values, as an unsigned magnitude
; args:    rdi = a, rsi = b
; returns: rax = gcd(|a|, |b|)
; -----------------------------------------------------------------------------
global umath_gcd_i64
umath_gcd_i64:
    mov     rax, rdi
    neg     rax
    cmovs   rax, rdi            ; |a| (INT64_MIN stays 2^63 as unsigned)
    mov     rdi, rax
    mov     rax, rsi
    neg     rax
    cmovs   rax, rsi
    mov     rsi, rax
    jmp     umath_gcd_u64

; -----------------------------------------------------------------------------
; umath_lcm_u64_checked - lcm with overflow detection
; args:    rdi = a, rsi = b, rdx = u64 *out (may be NULL)
; returns: eax = 1 and *out = lcm(a, b) if it fits; eax = 0 on overflow
;          (lcm with a zero operand is 0 and succeeds)
; -----------------------------------------------------------------------------
global umath_lcm_u64_checked
umath_lcm_u64_checked:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx
    xor     eax, eax
    test    rdi, rdi
    jz      .store
    test    rsi, rsi
    jz      .store
    call    umath_gcd_u64
    mov     rcx, rax
    mov     rax, rbx
    xor     edx, edx
    div     rcx                 ; a / g, exact
    mul     r12                 ; * b, 128-bit
    test    rdx, rdx
    jnz     .overflow
.store:
    test    r13, r13
    jz      .ok
    mov     [r13], rax
.ok:
    mov     eax, 1
    jmp     .out
.overflow:
    xor     eax, eax
.out:
    pop     r13
    pop     r12
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; umath_lcm_u64 - lcm, 0 on overflow
; args:    rdi = a, rsi = b
; returns: rax = lcm(a, b), or 0 if either is 0 or it does not fit
; -----------------------------------------------------------------------------
global umath_lcm_u64
umath_lcm_u64:
    sub     rsp, 8
    mov     qword [rsp], 0
    mov     rdx, rsp
    call    umath_lcm_u64_checked
    mov     rax, [rsp]          ; stays 0 on overflow
    add     rsp, 8
    ret

; -----------------------------------------------------------------------------
; umath_egcd_i64 - extended Euclid: a*x + b*y = gcd(|a|, |b|)
; args:    rdi = a, rsi = b, rdx = i64 *x, rcx = i64 *y (either may be NULL)
; returns: rax = g (unsigned)
; -----------------------------------------------------------------------------
global umath_egcd_i64
umath_egcd_i64:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r14, rdx            ; *x
    mov     r15, rcx            ; *y
    mov     r8, rdi             ; signs of a, b
    mov     r9, rsi
    mov     rax, rdi
    neg     rax
    cmovs   rax, rdi            ; r0 = |a|
    mov     rbx, rsi
    neg     rbx
    cmovs   rbx, rsi            ; r1 = |b|
    mov     r10d, 1             ; x0
    xor     r11d, r11d          ; x1
    xor     r12d, r12d          ; y0
    mov     r13d, 1             ; y1
.loop:
    test    rbx, rbx
    jz      .done
    xor     edx, edx
    div     rbx                 ; q = r0 / r1, rdx = r0 mod r1
    mov     rcx, rax            ; q
    mov     rax, rbx
    mov     rbx, rdx            ; (r0, r1) = (r1, r0 mod r1)
    mov     rdx, rcx
    imul    rdx, r11
    mov     rdi, r10
    sub     rdi, rdx            ; x0 - q*x1
    mov     r10, r11
    mov     r11, rdi
    mov     rdx, rcx
    imul    rdx, r13
    mov     rdi, r12
    sub     rdi, rdx            ; y0 - q*y1
    mov     r12, r13
    mov     r13, rdi
    jmp     .loop
.done:
    test    rax, rax
    jnz     .signs
    xor     r10d, r10d          ; gcd(0, 0): x = y = 0
.signs:
    test    r8, r8
    jns     .x_sign
    neg     r10                 ; |a|*x = a*(-x)
.x_sign:
    test    r9, r9
    jns     .y_sign
    neg     r12
.y_sign:
    test    r14, r14
    jz      .no_x
    mov     [r14], r10
.no_x:
    test    r15, r15
    jz      .no_y
    mov     [r15], r12
.no_y:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

%endif ; GUARD_LIB_UMATH_INTEGER_GCD_ASM
