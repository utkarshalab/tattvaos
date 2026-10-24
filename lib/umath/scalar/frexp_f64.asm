%ifndef GUARD_LIB_UMATH_SCALAR_FREXP_F64_ASM
%define GUARD_LIB_UMATH_SCALAR_FREXP_F64_ASM
; =============================================================================
; umath - unified math library
; scalar/frexp_f64.asm - exponent/mantissa decomposition for doubles
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
;   umath_frexp_f64(x, *e)   m in [0.5, 1) and *e with x = m * 2^e
;   umath_ilogb_f64(x)       unbiased exponent as int32: floor(log2|x|)
;   umath_logb_f64(x)        the same exponent as a double
;   umath_modf_f64(x, *ip)   fractional part, integral part to *ip
;
; All exact. Subnormals are normalized from their bits (frexp/ilogb/logb
; report their true exponent, down to -1074).
;
; Special cases:
;   frexp: +-0, +-Inf, NaN return x (NaN quieted) with *e = 0
;   ilogb: 0 -> INT32_MIN, NaN -> INT32_MIN, +-Inf -> INT32_MAX
;   logb:  +-0 -> -Inf, +-Inf -> +Inf, NaN -> NaN
;   modf:  +-Inf -> +-0 with *ip = +-Inf; NaN -> NaN, *ip = NaN; the
;          fractional part keeps x's sign (modf(-3.0) = -0.0)
; Pointer arguments may be NULL (the value is then just not stored).
; =============================================================================

bits 64

%include "lib/umath/cpuid/fallback.asm"

section .rodata
align 8
frexpf64_two_54:    dq 18014398509481984.0      ; 2^54
frexpf64_neg_inf:   dq 0xFFF0000000000000
frexpf64_inf:       dq 0x7FF0000000000000

section .text

; -----------------------------------------------------------------------------
; frexpf64__exp - internal: unbiased exponent of a finite nonzero double
; args:    rax = bits of |x|
; returns: rax = floor(log2|x|), rcx = biased exponent field (0 for subnormal)
; -----------------------------------------------------------------------------
frexpf64__exp:
    mov     rcx, rax
    shr     rcx, 52
    jz      .subnormal
    lea     rax, [rcx - 1023]
    ret
.subnormal:
    bsr     rax, rax            ; highest set mantissa bit, 0..51
    sub     rax, 1074
    ret

; -----------------------------------------------------------------------------
; umath_frexp_f64 - x = m * 2^e, 0.5 <= |m| < 1
; args:    xmm0 = x, rdi = int32 *e (may be NULL)
; returns: xmm0 = m
; -----------------------------------------------------------------------------
global umath_frexp_f64
umath_frexp_f64:
    movq    rax, xmm0
    mov     rdx, rax
    btr     rax, 63
    xor     rdx, rax            ; sign bit
    xor     r8d, r8d            ; e
    mov     rcx, 0x7FF0000000000000
    cmp     rax, rcx
    jae     .special            ; Inf, NaN
    test    rax, rax
    jz      .store              ; +-0
    mov     rcx, rax
    shr     rcx, 52             ; biased exponent
    jnz     .normal
    movq    xmm0, rax
    mulsd   xmm0, [rel frexpf64_two_54]  ; subnormal: scale up, exact
    movq    rax, xmm0
    mov     r8, -54
    mov     rcx, rax
    shr     rcx, 52
.normal:
    lea     r8, [r8 + rcx - 1022]
    mov     rcx, 0x800FFFFFFFFFFFFF
    and     rax, rcx
    mov     rcx, 0x3FE0000000000000  ; exponent of [0.5, 1)
    or      rax, rcx
    or      rax, rdx
    movq    xmm0, rax
    jmp     .store
.special:
    addsd   xmm0, xmm0          ; Inf unchanged, NaN quieted
.store:
    test    rdi, rdi
    jz      .out
    mov     [rdi], r8d
.out:
    ret

; -----------------------------------------------------------------------------
; umath_ilogb_f64 - unbiased exponent as an integer
; args:    xmm0 = x
; returns: eax = floor(log2|x|); INT32_MIN for 0 and NaN, INT32_MAX for Inf
; -----------------------------------------------------------------------------
global umath_ilogb_f64
umath_ilogb_f64:
    movq    rax, xmm0
    btr     rax, 63
    test    rax, rax
    jz      .low
    mov     rcx, 0x7FF0000000000000
    cmp     rax, rcx
    ja      .low                ; NaN
    je      .high               ; Inf
    call    frexpf64__exp
    ret
.low:
    mov     eax, 0x80000000
    ret
.high:
    mov     eax, 0x7FFFFFFF
    ret

; -----------------------------------------------------------------------------
; umath_logb_f64 - unbiased exponent as a double
; args:    xmm0 = x
; returns: xmm0 = floor(log2|x|); -Inf for +-0, +Inf for +-Inf, NaN for NaN
; -----------------------------------------------------------------------------
global umath_logb_f64
umath_logb_f64:
    movq    rax, xmm0
    btr     rax, 63
    test    rax, rax
    jz      .zero
    mov     rcx, 0x7FF0000000000000
    cmp     rax, rcx
    jae     .special
    call    frexpf64__exp
    cvtsi2sd xmm0, rax
    ret
.zero:
    movsd   xmm0, [rel frexpf64_neg_inf]
    ret
.special:
    movq    xmm0, rax           ; |x|: +Inf, or NaN
    addsd   xmm0, xmm0
    ret

; -----------------------------------------------------------------------------
; umath_modf_f64 - split into integral and fractional parts
; args:    xmm0 = x, rdi = double *ip (may be NULL)
; returns: xmm0 = x - trunc(x), with the sign of x; *ip = trunc(x)
; -----------------------------------------------------------------------------
global umath_modf_f64
umath_modf_f64:
    movq    rax, xmm0
    mov     rdx, rax
    btr     rax, 63
    xor     rdx, rax            ; sign bit
    mov     rcx, 0x7FF0000000000000
    cmp     rax, rcx
    ja      .nan
    je      .inf
    um_roundsd xmm1, xmm0, 3    ; trunc(x), keeps the sign
    subsd   xmm0, xmm1          ; exact
.sign:
    movq    rax, xmm0
    btr     rax, 63
    or      rax, rdx            ; the fraction carries x's sign (also +-0)
    movq    xmm0, rax
    test    rdi, rdi
    jz      .out
    movsd   [rdi], xmm1
.out:
    ret
.inf:
    movapd  xmm1, xmm0          ; integral part +-Inf
    xorpd   xmm0, xmm0          ; fraction +-0
    jmp     .sign
.nan:
    addsd   xmm0, xmm0
    movapd  xmm1, xmm0
    test    rdi, rdi
    jz      .out
    movsd   [rdi], xmm1
    ret

%endif ; GUARD_LIB_UMATH_SCALAR_FREXP_F64_ASM
