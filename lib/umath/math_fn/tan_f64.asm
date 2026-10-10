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

%include "lib/umath/math_fn/sin_f64.asm"
%include "lib/umath/math_fn/cos_f64.asm"

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
; tanf64__packed2 - internal: tan(x) of 2 lanes, bit-identical to
;                   umath_tan_f64 (= sin(x) / cos(x)) per lane
; args:    xmm0 = input values
; returns: xmm0 = results
; Runs the shared reduction once and takes both sin and cos from it.
; Clobbers xmm1-xmm10, no GPRs. Not declared global.
; -----------------------------------------------------------------------------
tanf64__packed2:
    call    sinf64__core2
    call    sinf64__select_sin
    movapd  xmm10, xmm0         ; sin(x)
    call    sinf64__select_cos   ; cos(x); core outputs preserved
    divpd   xmm10, xmm0
    movapd  xmm0, xmm10
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

    mov     rcx, rdx
    shr     rcx, 1              ; count of 2-double groups
    jz      .tail
.loop:
    movupd  xmm0, [rsi]
    call    tanf64__packed2  ; preserves rcx (no GPRs used)
    movupd  [rdi], xmm0
    add     rsi, 16
    add     rdi, 16
    dec     rcx
    jnz     .loop
.tail:
    and     rdx, 1
    jz      .done
.tail_loop:
    movsd   xmm0, [rsi]
    call    umath_tan_f64
    movsd   [rdi], xmm0
    add     rsi, 8
    add     rdi, 8
    dec     rdx
    jnz     .tail_loop
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

    mov     rcx, rsi
    shr     rcx, 1
    jz      .tail
.loop:
    movupd  xmm0, [rdi]
    call    tanf64__packed2
    movupd  [rdi], xmm0
    add     rdi, 16
    dec     rcx
    jnz     .loop
.tail:
    and     rsi, 1
    jz      .done
.tail_loop:
    movsd   xmm0, [rdi]
    call    umath_tan_f64
    movsd   [rdi], xmm0
    add     rdi, 8
    dec     rsi
    jnz     .tail_loop
.done:
    ret

%endif ; GUARD_LIB_UMATH_MATH_FN_TAN_F64_ASM
