%ifndef GUARD_LIB_UMATH_SCALAR_FREXP_F32_ASM
%define GUARD_LIB_UMATH_SCALAR_FREXP_F32_ASM
; =============================================================================
; umath - unified math library
; scalar/frexp_f32.asm - exponent/mantissa decomposition for floats
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; frexp, ilogb and logb widen to double (exact; float subnormals become
; normal doubles with the same value) and use the f64 routines, so they
; report the true exponent down to -149. frexp's mantissa is a float
; value, so narrowing it back is exact. modf works on the float directly
; (its integral part is stored as a float). Special cases as in
; frexp_f64.asm.
; =============================================================================

bits 64

%include "lib/umath/scalar/frexp_f64.asm"
%include "lib/umath/math_fn/loops.asm"
%include "lib/umath/cpuid/fallback.asm"

section .text

; umath_frexp_f32 (xmm0 = x, rdi = int32 *e) -> xmm0 = m
mathfn_f32_unary umath_frexp_f32, umath_frexp_f64
; umath_logb_f32 (xmm0 = x) -> xmm0
mathfn_f32_unary umath_logb_f32, umath_logb_f64

; -----------------------------------------------------------------------------
; umath_ilogb_f32 - unbiased exponent as an integer
; args:    xmm0 = x (f32)
; returns: eax = floor(log2|x|); INT32_MIN for 0 and NaN, INT32_MAX for Inf
; -----------------------------------------------------------------------------
global umath_ilogb_f32
umath_ilogb_f32:
    cvtss2sd xmm0, xmm0
    jmp     umath_ilogb_f64

; -----------------------------------------------------------------------------
; umath_modf_f32 - split into integral and fractional parts
; args:    xmm0 = x (f32), rdi = float *ip (may be NULL)
; returns: xmm0 = x - trunc(x), with the sign of x; *ip = trunc(x)
; -----------------------------------------------------------------------------
global umath_modf_f32
umath_modf_f32:
    movd    eax, xmm0
    mov     edx, eax
    btr     eax, 31
    xor     edx, eax            ; sign bit
    cmp     eax, 0x7F800000
    ja      .nan
    je      .inf
    um_roundss xmm1, xmm0, 3    ; trunc(x)
    subss   xmm0, xmm1          ; exact
.sign:
    movd    eax, xmm0
    btr     eax, 31
    or      eax, edx
    movd    xmm0, eax
    test    rdi, rdi
    jz      .out
    movss   [rdi], xmm1
.out:
    ret
.inf:
    movaps  xmm1, xmm0
    xorps   xmm0, xmm0
    jmp     .sign
.nan:
    addss   xmm0, xmm0
    movaps  xmm1, xmm0
    test    rdi, rdi
    jz      .out
    movss   [rdi], xmm1
    ret

%endif ; GUARD_LIB_UMATH_SCALAR_FREXP_F32_ASM
