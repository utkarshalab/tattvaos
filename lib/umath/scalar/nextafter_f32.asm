%ifndef GUARD_LIB_UMATH_SCALAR_NEXTAFTER_F32_ASM
%define GUARD_LIB_UMATH_SCALAR_NEXTAFTER_F32_ASM
; =============================================================================
; umath - unified math library
; scalar/nextafter_f32.asm - neighbouring representable floats
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
;   umath_nextafter_f32(x, y)  the float next to x in the direction of y
;   umath_nextup_f32(x)        the least float greater than x
;   umath_nextdown_f32(x)      the greatest float less than x
;
; Positive and negative values are both ordered by their magnitude bits,
; so one step is +-1 on the bit pattern: away from zero adds one, toward
; zero subtracts one. That walks through the subnormals, steps from the
; largest finite value to Inf and from Inf back to the largest finite.
;
;   - x == y returns y (so nextafter(+0, -0) = -0);
;   - x = +-0 steps to the smallest subnormal with y's sign;
;   - nextup(+Inf) = +Inf, nextdown(-Inf) = -Inf;
;   - NaN in, NaN out (quieted).
; =============================================================================

bits 64

section .rodata
align 8
nextf32_pinf:       dd 0x7F800000
nextf32_ninf:       dd 0xFF800000

section .text

; -----------------------------------------------------------------------------
; umath_nextafter_f32 - next float after x toward y
; args:    xmm0 = x, xmm1 = y
; returns: xmm0 = result
; -----------------------------------------------------------------------------
global umath_nextafter_f32
umath_nextafter_f32:
    ucomiss  xmm0, xmm1
    jp      .nan
    je      .equal
    movd    eax, xmm0
    mov     ecx, eax
    btr     ecx, 31
    test    ecx, ecx
    jz      .from_zero
    comiss   xmm0, xmm1
    jb      .up
    test    eax, eax           ; moving down
    js      .away
    jmp     .toward
.up:
    test    eax, eax
    js      .toward
.away:
    inc     eax
    movd    xmm0, eax
    ret
.toward:
    dec     eax
    movd    xmm0, eax
    ret
.from_zero:
    movd    eax, xmm1
    shr     eax, 31
    shl     eax, 31           ; y's sign bit
    or      eax, 1             ; smallest subnormal
    movd    xmm0, eax
    ret
.equal:
    movaps   xmm0, xmm1
    ret
.nan:
    addss   xmm0, xmm1
    ret

; -----------------------------------------------------------------------------
; umath_nextup_f32 / umath_nextdown_f32
; args:    xmm0 = x
; returns: xmm0 = next float above / below x
; -----------------------------------------------------------------------------
global umath_nextup_f32
umath_nextup_f32:
    movss   xmm1, [rel nextf32_pinf]
    jmp     umath_nextafter_f32

global umath_nextdown_f32
umath_nextdown_f32:
    movss   xmm1, [rel nextf32_ninf]
    jmp     umath_nextafter_f32

%endif ; GUARD_LIB_UMATH_SCALAR_NEXTAFTER_F32_ASM
