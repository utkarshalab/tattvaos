%ifndef GUARD_LIB_UMATH_SCALAR_NEXTAFTER_F64_ASM
%define GUARD_LIB_UMATH_SCALAR_NEXTAFTER_F64_ASM
; =============================================================================
; umath - unified math library
; scalar/nextafter_f64.asm - neighbouring representable doubles
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
;   umath_nextafter_f64(x, y)  the double next to x in the direction of y
;   umath_nextup_f64(x)        the least double greater than x
;   umath_nextdown_f64(x)      the greatest double less than x
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
nextf64_pinf:       dq 0x7FF0000000000000
nextf64_ninf:       dq 0xFFF0000000000000

section .text

; -----------------------------------------------------------------------------
; umath_nextafter_f64 - next double after x toward y
; args:    xmm0 = x, xmm1 = y
; returns: xmm0 = result
; -----------------------------------------------------------------------------
global umath_nextafter_f64
umath_nextafter_f64:
    ucomisd  xmm0, xmm1
    jp      .nan
    je      .equal
    movq    rax, xmm0
    mov     rcx, rax
    btr     rcx, 63
    test    rcx, rcx
    jz      .from_zero
    comisd   xmm0, xmm1
    jb      .up
    test    rax, rax           ; moving down
    js      .away
    jmp     .toward
.up:
    test    rax, rax
    js      .toward
.away:
    inc     rax
    movq    xmm0, rax
    ret
.toward:
    dec     rax
    movq    xmm0, rax
    ret
.from_zero:
    movq    rax, xmm1
    shr     rax, 63
    shl     rax, 63           ; y's sign bit
    or      rax, 1             ; smallest subnormal
    movq    xmm0, rax
    ret
.equal:
    movapd   xmm0, xmm1
    ret
.nan:
    addsd   xmm0, xmm1
    ret

; -----------------------------------------------------------------------------
; umath_nextup_f64 / umath_nextdown_f64
; args:    xmm0 = x
; returns: xmm0 = next double above / below x
; -----------------------------------------------------------------------------
global umath_nextup_f64
umath_nextup_f64:
    movsd   xmm1, [rel nextf64_pinf]
    jmp     umath_nextafter_f64

global umath_nextdown_f64
umath_nextdown_f64:
    movsd   xmm1, [rel nextf64_ninf]
    jmp     umath_nextafter_f64

%endif ; GUARD_LIB_UMATH_SCALAR_NEXTAFTER_F64_ASM
