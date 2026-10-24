%ifndef GUARD_LIB_UMATH_INTEGER_MODULAR_ASM
%define GUARD_LIB_UMATH_INTEGER_MODULAR_ASM
; =============================================================================
; umath - unified math library
; integer/modular.asm - modular arithmetic and integer powers on u64
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
;   umath_mulmod_u64(a, b, m)           a*b mod m, exact for every u64
;   umath_powmod_u64(b, e, m)           b^e mod m
;   umath_modinv_u64(a, m)              x in [0, m) with a*x = 1 (mod m),
;                                       0 if gcd(a, m) != 1
;   umath_ipow_u64(b, e)                b^e mod 2^64 (wrapping)
;   umath_ipow_u64_checked(b, e, *out)  eax = 1 and *out = b^e if it fits,
;                                       eax = 0 on overflow
;
; mulmod reduces a and b first, then divides the full 128-bit product
; a*b by m (one mul, one div): with a, b < m the quotient is below m, so
; the division cannot fault, and nothing overflows. powmod is square-and-
; multiply on top of it (at most 128 mulmods). m = 0 is treated as
; "no modulus defined" and returns 0; m = 1 returns 0 as well.
;
; modinv runs the extended Euclidean algorithm on (a mod m, m) keeping
; only the coefficient of a, which stays within (-m, m).
;
; ipow_u64_checked squares the base only while exponent bits remain, so
; a final, unused square cannot report a spurious overflow.
; =============================================================================

bits 64

section .text

; -----------------------------------------------------------------------------
; umath_mulmod_u64 - a*b mod m
; args:    rdi = a, rsi = b, rdx = m
; returns: rax = (a*b) mod m, 0 for m = 0
; -----------------------------------------------------------------------------
global umath_mulmod_u64
umath_mulmod_u64:
    mov     rcx, rdx
    xor     eax, eax
    test    rcx, rcx
    jz      .done
    mov     rax, rdi
    xor     edx, edx
    div     rcx
    mov     r8, rdx             ; a mod m
    mov     rax, rsi
    xor     edx, edx
    div     rcx                 ; rdx = b mod m
    mov     rax, rdx
    mul     r8                  ; < m^2
    div     rcx
    mov     rax, rdx
.done:
    ret

; -----------------------------------------------------------------------------
; umath_powmod_u64 - b^e mod m (square and multiply)
; args:    rdi = b, rsi = e, rdx = m
; returns: rax = b^e mod m; 0 for m = 0 or 1; 0^0 = 1 mod m
; -----------------------------------------------------------------------------
global umath_powmod_u64
umath_powmod_u64:
    mov     rcx, rdx            ; m
    xor     eax, eax
    cmp     rcx, 1
    jbe     .done
    mov     rax, rdi
    xor     edx, edx
    div     rcx
    mov     r8, rdx             ; base mod m
    mov     r9d, 1              ; result
.loop:
    test    rsi, 1
    jz      .square
    mov     rax, r9
    mul     r8
    div     rcx
    mov     r9, rdx             ; result *= base
.square:
    shr     rsi, 1
    jz      .finish
    mov     rax, r8
    mul     r8
    div     rcx
    mov     r8, rdx             ; base *= base
    jmp     .loop
.finish:
    mov     rax, r9
.done:
    ret

; -----------------------------------------------------------------------------
; umath_modinv_u64 - modular inverse
; args:    rdi = a, rsi = m
; returns: rax = a^-1 mod m in [0, m), or 0 when none exists (gcd != 1,
;          or m <= 1)
; -----------------------------------------------------------------------------
global umath_modinv_u64
umath_modinv_u64:
    xor     eax, eax
    cmp     rsi, 1
    jbe     .done
    mov     rax, rdi
    xor     edx, edx
    div     rsi
    mov     rcx, rsi            ; r0 = m
    mov     r8, rdx             ; r1 = a mod m
    xor     r9d, r9d            ; t0 = 0
    mov     r10d, 1             ; t1 = 1
.loop:
    test    r8, r8
    jz      .end
    mov     rax, rcx
    xor     edx, edx
    div     r8                  ; q = r0 / r1
    mov     rcx, r8
    mov     r8, rdx             ; (r0, r1) = (r1, r0 mod r1)
    imul    rax, r10
    mov     r11, r9
    sub     r11, rax            ; t0 - q*t1
    mov     r9, r10
    mov     r10, r11
    jmp     .loop
.end:
    xor     eax, eax
    cmp     rcx, 1
    jne     .done               ; not invertible
    mov     rax, r9
    test    rax, rax
    jns     .done
    add     rax, rsi            ; into [0, m)
.done:
    ret

; -----------------------------------------------------------------------------
; umath_ipow_u64_checked - b^e with overflow detection
; args:    rdi = b, rsi = e, rdx = u64 *out (may be NULL)
; returns: eax = 1 and *out = b^e if it fits in 64 bits, else eax = 0
; -----------------------------------------------------------------------------
global umath_ipow_u64_checked
umath_ipow_u64_checked:
    mov     r10, rdx            ; out
    mov     r8, rdi             ; base
    mov     r9d, 1              ; result
    xor     r11d, r11d          ; overflow flag
.loop:
    test    rsi, 1
    jz      .square
    mov     rax, r9
    mul     r8
    test    rdx, rdx
    jz      .mul_ok
    mov     r11d, 1
.mul_ok:
    mov     r9, rax
.square:
    shr     rsi, 1
    jz      .finish
    mov     rax, r8
    mul     r8
    test    rdx, rdx
    jz      .sq_ok
    ; the base overflowed: fatal only if the result still multiplies by
    ; it, i.e. if any exponent bit is still set (true here) and the
    ; current result is nonzero
    test    r9, r9
    jz      .sq_ok
    mov     r11d, 1
.sq_ok:
    mov     r8, rax
    jmp     .loop
.finish:
    xor     eax, eax
    test    r11d, r11d
    jnz     .out
    test    r10, r10
    jz      .ok
    mov     [r10], r9
.ok:
    mov     eax, 1
.out:
    ret

; -----------------------------------------------------------------------------
; umath_ipow_u64 - b^e mod 2^64
; args:    rdi = b, rsi = e
; returns: rax = b^e, wrapped to 64 bits
; -----------------------------------------------------------------------------
global umath_ipow_u64
umath_ipow_u64:
    mov     rax, 1
    mov     r8, rdi
.loop:
    test    rsi, 1
    jz      .square
    imul    rax, r8
.square:
    shr     rsi, 1
    jz      .done
    imul    r8, r8
    jmp     .loop
.done:
    ret

%endif ; GUARD_LIB_UMATH_INTEGER_MODULAR_ASM
