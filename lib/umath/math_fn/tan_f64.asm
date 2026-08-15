%ifndef GUARD_LIB_UMATH_MATH_FN_TAN_F64_ASM
%define GUARD_LIB_UMATH_MATH_FN_TAN_F64_ASM
; =============================================================================
; umath - unified math library
; math_fn/tan_f64.asm - double-precision tangent
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; tan(x) = sin(x) / cos(x), composed from umath_sin_f64/umath_cos_f64 —
; see tan_f32.asm for the full rationale (same reasoning, double
; precision here). x held in xmm5, sin(x) held in xmm7 across the second
; call: verified by inspection that neither umath_sin_f64 nor
; umath_cos_f64 touches xmm5 or xmm7.
; =============================================================================

bits 64

section .text

; -----------------------------------------------------------------------------
; umath_tan_f64 - scalar double-precision tangent
; args:    xmm0 = input value (x), radians
; returns: xmm0 = tan(x); NaN for NaN or +/-Inf input
; -----------------------------------------------------------------------------
global umath_tan_f64
umath_tan_f64:
    movapd  xmm5, xmm0
    call    umath_sin_f64
    movapd  xmm7, xmm0            ; xmm7 = sin(x)
    movapd  xmm0, xmm5
    call    umath_cos_f64          ; xmm0 = cos(x)
    movapd  xmm1, xmm0
    movapd  xmm0, xmm7
    divsd   xmm0, xmm1
    ret

; -----------------------------------------------------------------------------
; umath_tan_f64_array - tan(x) for an array of doubles
; args:    rdi = destination pointer (dst)
;          rsi = source pointer (src)
;          rdx = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_tan_f64_array
umath_tan_f64_array:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done
    test    rdx, rdx
    jz      .done

.loop:
    movsd   xmm0, [rsi]
    call    umath_tan_f64
    movsd   [rdi], xmm0
    add     rsi, 8
    add     rdi, 8
    dec     rdx
    jnz     .loop

.done:
    ret

; -----------------------------------------------------------------------------
; umath_tan_f64_inplace - tan(x) in place for a double array
; args:    rdi = buffer pointer (buf)
;          rsi = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_tan_f64_inplace
umath_tan_f64_inplace:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done

.loop:
    movsd   xmm0, [rdi]
    call    umath_tan_f64
    movsd   [rdi], xmm0
    add     rdi, 8
    dec     rsi
    jnz     .loop

.done:
    ret

%endif ; GUARD_LIB_UMATH_MATH_FN_TAN_F64_ASM
