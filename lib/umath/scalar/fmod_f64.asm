%ifndef GUARD_LIB_UMATH_SCALAR_FMOD_F64_ASM
%define GUARD_LIB_UMATH_SCALAR_FMOD_F64_ASM
; =============================================================================
; umath - unified math library
; scalar/fmod_f64.asm - exact floating-point remainders for doubles
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
;   umath_fmod_f64(x, y)          x - n*y, n = trunc(x/y); sign of x
;   umath_remainder_f64(x, y)     x - n*y, n = x/y rounded half to even
;   umath_remquo_f64(x, y, *quo)  remainder, and the quotient's low 3 bits
;                                 with the sign of x/y stored to *quo
;
; All three are exact: the result is always representable, and it is
; computed without any rounding. Both operands are taken as integer
; mantissas, |x| = mx * 2^(ex-1075) and |y| = my * 2^(ey-1075) (biased
; exponents, subnormals included as is), and the reduction is a long
; division on those integers:
;
;     r = mx mod my, then (ex - ey) times: r = (r * 2) mod my
;
; done in steps of up to 63 bits at once (a 128-by-64-bit `div` of
; r << s; r < my < 2^53 keeps the quotient below 2^63), so at most 34
; divisions even for the widest exponent gap. The quotient's low bits are
; carried along for remainder/remquo. The remainder r * 2^(ey-1075) is
; then converted exactly (r < 2^53, scalbn exact for a representable
; value).
;
; remainder rounds the quotient half to even: r -= |y| when r > |y|/2,
; or r == |y|/2 with an odd quotient (compared as r+r against |y| when
; |y| is tiny, where |y|/2 would round).
;
; Special cases (C99 / IEEE 754): x infinite or y zero -> NaN; y infinite
; -> x; x zero -> x; NaN -> NaN. remquo stores 0 for the special cases.
; =============================================================================

bits 64

%include "lib/umath/math_fn/scalbn_f64.asm"
%include "lib/umath/math_fn/loops.asm"

section .rodata
align 8
fmodf64_mant:       dq 0x000FFFFFFFFFFFFF
fmodf64_inf:        dq 0x7FF0000000000000
fmodf64_nan:        dq 0x7FF8000000000000
fmodf64_half:       dq 0.5
fmodf64_tiny:       dq 0x0020000000000000       ; 2^-1021

section .text

; -----------------------------------------------------------------------------
; fmodf64__core - internal: fmod of two positive finite nonzero doubles
; args:    rax = bits of |x|, rcx = bits of |y|, xmm0 = |x|
; returns: xmm0 = |x| mod |y| (exact), r10 = quotient (low 64 bits)
; Clobbers rax, rcx, rdx, rsi, rdi, r8, r9, r11, xmm1.
; -----------------------------------------------------------------------------
fmodf64__core:
    mov     rdx, [rel fmodf64_mant]
    mov     r8, rax
    shr     r8, 52              ; ex (biased; 0 = subnormal)
    and     rax, rdx            ; mx
    test    r8, r8
    jz      .x_sub
    bts     rax, 52
    jmp     .x_done
.x_sub:
    mov     r8d, 1
.x_done:
    mov     r9, rcx
    shr     r9, 52              ; ey
    mov     rsi, rcx
    and     rsi, rdx            ; my
    test    r9, r9
    jz      .y_sub
    bts     rsi, 52
    jmp     .y_done
.y_sub:
    mov     r9d, 1
.y_done:
    xor     r10d, r10d
    cmp     r8, r9
    jb      .smaller            ; |x| < |y| by exponent alone
    xor     edx, edx
    div     rsi                 ; rax = mx / my, rdx = mx mod my
    mov     r10, rax
    mov     r11, r8
    sub     r11, r9             ; exponent gap still to reduce
.step:
    test    r11, r11
    jz      .reduced
    mov     rcx, r11
    cmp     rcx, 63
    jbe     .count
    mov     ecx, 63
.count:
    mov     rax, rdx
    xor     edx, edx
    shld    rdx, rax, cl
    shl     rax, cl             ; rdx:rax = r << s
    div     rsi
    shl     r10, cl
    add     r10, rax            ; quotient = quotient << s + step
    sub     r11, rcx
    jmp     .step
.reduced:
    xorpd   xmm0, xmm0
    test    rdx, rdx
    jz      .zero
    cvtsi2sd xmm0, rdx          ; exact: r < 2^53
    lea     rdi, [r9 - 1075]
    call    umath_scalbn_f64    ; exact: the remainder is representable
.zero:
    ret
.smaller:
    ret                         ; |x| < |y|: xmm0 still holds |x|

; -----------------------------------------------------------------------------
; fmodf64__classify - internal: shared special-case screening
; args:    xmm0 = x, xmm1 = y
; returns: ZF=0 and xmm0 = result if a special case applies (NaN, x
;          infinite, y zero, y infinite, x zero); ZF=1 to continue with
;          rax = |x| bits, rcx = |y| bits, rdx = sign bit of x
; -----------------------------------------------------------------------------
fmodf64__classify:
    ucomisd xmm0, xmm1
    jp      .nan_in
    movq    rax, xmm0
    mov     rdx, rax
    btr     rax, 63
    xor     rdx, rax            ; sign of x
    movq    rcx, xmm1
    btr     rcx, 63
    cmp     rax, [rel fmodf64_inf]
    je      .invalid            ; x infinite
    test    rcx, rcx
    jz      .invalid            ; y zero
    cmp     rcx, [rel fmodf64_inf]
    je      .keep_x             ; y infinite
    test    rax, rax
    jz      .keep_x             ; x zero
    xor     r8d, r8d            ; ZF = 1: general case
    ret
.nan_in:
    addsd   xmm0, xmm1
    jmp     .special
.invalid:
    movsd   xmm0, [rel fmodf64_nan]
.keep_x:
.special:
    or      r8d, -1             ; ZF = 0
    ret

; -----------------------------------------------------------------------------
; umath_fmod_f64 - x - trunc(x/y)*y, exact
; args:    xmm0 = x, xmm1 = y
; returns: xmm0 = fmod(x, y), sign of x
; -----------------------------------------------------------------------------
global umath_fmod_f64
umath_fmod_f64:
    call    fmodf64__classify
    jnz     .done
    push    rdx
    movq    xmm0, rax           ; |x|, returned as is when |x| < |y|
    call    fmodf64__core
    pop     rdx
    movq    rax, xmm0
    or      rax, rdx
    movq    xmm0, rax
.done:
    ret

; -----------------------------------------------------------------------------
; fmodf64__remainder - internal: IEEE remainder magnitude and quotient
; args:    as fmodf64__core, plus xmm0 = |x|
; returns: xmm0 = remainder with the sign of x/y removed (may be negative:
;          r - |y|), r10 = rounded quotient (low bits)
; -----------------------------------------------------------------------------
fmodf64__remainder:
    push    rcx                 ; |y| bits
    call    fmodf64__core       ; xmm0 = r, r10 = trunc quotient
    pop     rcx
    movq    xmm1, rcx           ; p = |y|
    cmp     rcx, [rel fmodf64_tiny]
    jb      .tiny_p
    movapd  xmm2, xmm1
    mulsd   xmm2, [rel fmodf64_half]  ; p/2, exact here
    ucomisd xmm0, xmm2
    ja      .round_up
    jb      .done
    jmp     .tie
.tiny_p:
    movapd  xmm2, xmm0
    addsd   xmm2, xmm0          ; 2r, exact (r is tiny)
    ucomisd xmm2, xmm1
    ja      .round_up
    jb      .done
.tie:
    test    r10, 1
    jz      .done               ; even quotient: keep r
.round_up:
    subsd   xmm0, xmm1          ; r - p, exact
    inc     r10
.done:
    ret

; -----------------------------------------------------------------------------
; umath_remainder_f64 - IEEE 754 remainder
; args:    xmm0 = x, xmm1 = y
; returns: xmm0 = x - n*y, n = x/y rounded half to even
; -----------------------------------------------------------------------------
global umath_remainder_f64
umath_remainder_f64:
    call    fmodf64__classify
    jnz     .done
    push    rdx
    movq    xmm0, rax
    call    fmodf64__remainder
    pop     rdx
    movq    rax, xmm0
    xor     rax, rdx            ; sign of x applied to the signed magnitude
    movq    xmm0, rax
.done:
    ret

; -----------------------------------------------------------------------------
; umath_remquo_f64 - remainder plus the quotient's low bits
; args:    xmm0 = x, xmm1 = y, rdi = int32 *quo (may be NULL)
; returns: xmm0 = remainder(x, y); *quo = +-(n mod 8), sign of x/y
; -----------------------------------------------------------------------------
global umath_remquo_f64
umath_remquo_f64:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi            ; quo
    movq    r12, xmm1           ; y bits, for the quotient's sign
    call    fmodf64__classify
    mov     r13d, 0
    jnz     .store
    push    rdx
    push    rdx                 ; (keeps the stack aligned)
    movq    xmm0, rax
    call    fmodf64__remainder
    pop     rdx
    pop     rdx
    movq    rax, xmm0
    xor     rax, rdx
    movq    xmm0, rax
    mov     r13, r10
    and     r13d, 7
    xor     rdx, r12            ; sign(x) ^ sign(y)
    jns     .store
    neg     r13d
.store:
    test    rbx, rbx
    jz      .out
    mov     [rbx], r13d
.out:
    pop     r13
    pop     r12
    pop     rbx
    ret

mathfn_binary_arrays umath_fmod_f64, umath_fmod_f64, 8
mathfn_binary_arrays umath_remainder_f64, umath_remainder_f64, 8

%endif ; GUARD_LIB_UMATH_SCALAR_FMOD_F64_ASM
