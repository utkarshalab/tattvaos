%ifndef GUARD_LIB_UMATH_MATH_FN_TAN_F32_ASM
%define GUARD_LIB_UMATH_MATH_FN_TAN_F32_ASM
; =============================================================================
; umath - unified math library
; math_fn/tan_f32.asm - single-precision tangent
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; tan(x) = sin(x) / cos(x), composed directly from umath_sin_f32 and
; umath_cos_f32 (same directory) rather than its own range reduction —
; same reasoning as pow_f32.asm composing log_f32/exp_f32: those two are
; already verified, and re-deriving tan's own polynomial buys accuracy
; this library doesn't need at the cost of a second bug-prone
; implementation of range reduction.
;
; No special-case handling for x near an odd multiple of pi/2 (where cos
; is near zero): hardware divss already does the right IEEE thing —
; divide-by-a-tiny-number produces a very large result, and an exact zero
; cos produces a signed Inf, which is the correct limiting behavior for
; tan's vertical asymptotes. NaN/Inf input already returns NaN from both
; sin_f32 and cos_f32, so it propagates here for free.
;
; x is held in xmm5 across both calls: umath_sin_f32/umath_cos_f32 use
; xmm0-4 and xmm6 internally (verified by inspection, not assumed) but
; never touch xmm5, so it survives untouched as scratch for the second
; call's input.
; =============================================================================

bits 64

%include "lib/umath/math_fn/sin_f32.asm"
%include "lib/umath/math_fn/cos_f32.asm"

section .text

; -----------------------------------------------------------------------------
; umath_tan_f32 - scalar single-precision tangent
; args:    xmm0 = input value (x), radians
; returns: xmm0 = tan(x); NaN for NaN or +/-Inf input
; -----------------------------------------------------------------------------
global umath_tan_f32
umath_tan_f32:
    movaps  xmm5, xmm0
    call    umath_sin_f32
    movaps  xmm7, xmm0            ; xmm7 = sin(x)
    movaps  xmm0, xmm5
    call    umath_cos_f32          ; xmm0 = cos(x)
    movaps  xmm1, xmm0
    movaps  xmm0, xmm7
    divss   xmm0, xmm1
    ret

; -----------------------------------------------------------------------------
; tanf32__packed4 - internal: tan(x) of 4 lanes, bit-identical to
;                   umath_tan_f32 (= sin(x) / cos(x)) per lane
; args:    xmm0 = input values
; returns: xmm0 = results
; Runs the shared reduction once and takes both sin and cos from it.
; Clobbers xmm1-xmm14, no GPRs. Not declared global.
; -----------------------------------------------------------------------------
tanf32__packed4:
    call    sinf32__core4
    call    sinf32__select_sin
    movaps  xmm14, xmm0         ; sin(x)
    call    sinf32__select_cos   ; cos(x); core outputs preserved
    divps   xmm14, xmm0
    movaps  xmm0, xmm14
    ret

; -----------------------------------------------------------------------------
; umath_tan_f32_array - tan(x) for an array of floats
; args:    rdi = destination pointer (dst)
;          rsi = source pointer (src)
;          rdx = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_tan_f32_array
umath_tan_f32_array:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done
    test    rdx, rdx
    jz      .done

    mov     rcx, rdx
    shr     rcx, 2              ; count of 4-float groups
    jz      .tail
.loop:
    movups  xmm0, [rsi]
    call    tanf32__packed4  ; preserves rcx (no GPRs used)
    movups  [rdi], xmm0
    add     rsi, 16
    add     rdi, 16
    dec     rcx
    jnz     .loop
.tail:
    and     rdx, 3
    jz      .done
.tail_loop:
    movss   xmm0, [rsi]
    call    umath_tan_f32
    movss   [rdi], xmm0
    add     rsi, 4
    add     rdi, 4
    dec     rdx
    jnz     .tail_loop
.done:
    ret

; -----------------------------------------------------------------------------
; umath_tan_f32_inplace - tan(x) in place for a float array
; args:    rdi = buffer pointer (buf)
;          rsi = size of array (count)
; returns: void
; -----------------------------------------------------------------------------
global umath_tan_f32_inplace
umath_tan_f32_inplace:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done

    mov     rcx, rsi
    shr     rcx, 2
    jz      .tail
.loop:
    movups  xmm0, [rdi]
    call    tanf32__packed4
    movups  [rdi], xmm0
    add     rdi, 16
    dec     rcx
    jnz     .loop
.tail:
    and     rsi, 3
    jz      .done
.tail_loop:
    movss   xmm0, [rdi]
    call    umath_tan_f32
    movss   [rdi], xmm0
    add     rdi, 4
    dec     rsi
    jnz     .tail_loop
.done:
    ret

%endif ; GUARD_LIB_UMATH_MATH_FN_TAN_F32_ASM
