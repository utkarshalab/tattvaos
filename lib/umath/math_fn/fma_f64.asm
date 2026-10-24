%ifndef GUARD_LIB_UMATH_MATH_FN_FMA_F64_ASM
%define GUARD_LIB_UMATH_MATH_FN_FMA_F64_ASM
; =============================================================================
; umath - unified math library
; math_fn/fma_f64.asm - fused multiply-add: x*y + z rounded once
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; With FMA3 (cpuid/: UMATH_CPU_FMA, which also needs OS-enabled AVX state)
; this is one vfmadd213sd. Without it, an exact integer emulation computes
; the same correctly rounded result:
;
;   1. x = mx*2^ex, y = my*2^ey, z = mz*2^ez with integer mantissas
;      (subnormals taken as they are).
;   2. P = mx*my exactly (one 64x64 -> 128-bit mul), exponent ex + ey.
;   3. P and mz are both shifted so their top bit is bit 125 of a 128-bit
;      value, then the one with the smaller exponent is shifted right to
;      the other's, every bit shifted out folded into a sticky bit.
;   4. Same signs add, opposite signs subtract the smaller magnitude from
;      the larger (the sign is the larger one's). An exact zero is +0.
;   5. The sum is rounded once to p bits, half to even, its lowest bit no
;      lower than 2^emin -- p = 53, emin = -1074 for double; the f32 fma
;      reuses this core with p = 24, emin = -149, so it is correctly
;      rounded as a float directly rather than double-rounded.
;   6. mantissa * 2^e is converted exactly (scalbn); overflow becomes Inf.
;
; Special operands are handled before the core: a non-finite x or y, a
; zero x or y, or a zero z make x*y + z exact or correct in plain
; arithmetic; finite x, y with infinite or NaN z return z.
; =============================================================================

bits 64

%include "lib/umath/math_fn/scalbn_f64.asm"
%include "lib/umath/cpuid/fallback.asm"

section .rodata
align 8
fmaf64_exp_mask:    dq 0x7FF0000000000000
fmaf64_mant:        dq 0x000FFFFFFFFFFFFF

section .text

; shift %1:%2 (hi:lo) left by cl (0..127); clobbers rcx
%macro fmaf64_shl128 2
    cmp     ecx, 64
    jb      %%short
    mov     %1, %2
    xor     %2, %2
    sub     ecx, 64
    shl     %1, cl
    jmp     %%done
%%short:
    shld    %1, %2, cl
    shl     %2, cl
%%done:
%endmacro

; shift %1:%2 (hi:lo) right by rcx (any size); r10 = 1 if any bit set was
; shifted out, else 0. Clobbers rax, rcx.
%macro fmaf64_shr128 2
    xor     r10d, r10d
    cmp     rcx, 128
    jb      %%under128
    or      %2, %1
    setnz   r10b
    xor     %1, %1
    xor     %2, %2
    jmp     %%done
%%under128:
    cmp     ecx, 64
    jb      %%under64
    test    %2, %2
    setnz   r10b
    mov     %2, %1
    xor     %1, %1
    sub     ecx, 64
%%under64:
    test    ecx, ecx
    jz      %%done
    mov     rax, %2
    shr     rax, cl
    shl     rax, cl
    cmp     rax, %2
    je      %%kept
    mov     r10d, 1
%%kept:
    shrd    %2, %1, cl
    shr     %1, cl
%%done:
%endmacro

; -----------------------------------------------------------------------------
; fmaf64__decomp - internal: rax = bits (sign ignored) of a finite double
; returns: rax = integer mantissa, rdx = exponent of its lowest bit
; Clobbers rcx.
; -----------------------------------------------------------------------------
fmaf64__decomp:
    mov     rdx, rax
    shr     rdx, 52
    and     edx, 0x7FF
    mov     rcx, [rel fmaf64_mant]
    and     rax, rcx
    test    edx, edx
    jz      .subnormal
    bts     rax, 52
    sub     rdx, 1075
    ret
.subnormal:
    mov     rdx, -1074
    ret

; -----------------------------------------------------------------------------
; fmaf64__core - internal: x*y + z rounded once to p bits
; args:    xmm0 = x, xmm1 = y, xmm2 = z (finite, all three nonzero)
;          r8 = p (53 or 24), r9 = emin (lowest result bit exponent)
; returns: xmm0 = the rounded result as a double (exact conversion)
; -----------------------------------------------------------------------------
fmaf64__core:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    ; x
    movq    rax, xmm0
    mov     r11, rax
    shr     r11, 63             ; bit 0 = sign of x*y (so far x)
    call    fmaf64__decomp
    mov     rbx, rax            ; mx
    mov     r14, rdx            ; ex
    ; y
    movq    rax, xmm1
    mov     rcx, rax
    shr     rcx, 63
    xor     r11, rcx
    call    fmaf64__decomp
    add     r14, rdx            ; eP = ex + ey
    mul     rbx                 ; rdx:rax = mx*my
    mov     r12, rdx
    mov     r13, rax            ; P = r12:r13
    ; z
    movq    rax, xmm2
    mov     rcx, rax
    shr     rcx, 63
    shl     rcx, 1
    or      r11, rcx            ; bit 1 = sign of z
    call    fmaf64__decomp
    xor     r15d, r15d
    mov     rdi, rax            ; Z = r15:rdi
    mov     rsi, rdx            ; eZ

    ; top bit of P to bit 125
    bsr     rcx, r12
    jz      .p_low
    add     ecx, 64
    jmp     .p_msb
.p_low:
    bsr     rcx, r13
.p_msb:
    mov     eax, 125
    sub     eax, ecx
    sub     r14, rax
    mov     ecx, eax
    fmaf64_shl128 r12, r13
    ; top bit of Z to bit 125
    bsr     rcx, rdi
    mov     eax, 125
    sub     eax, ecx
    sub     rsi, rax
    mov     ecx, eax
    fmaf64_shl128 r15, rdi

    ; align to the larger exponent
    mov     rcx, r14
    sub     rcx, rsi            ; d = eP - eZ
    jl      .p_smaller
    fmaf64_shr128 r15, rdi
    or      rdi, r10            ; sticky
    mov     rsi, r14            ; common exponent
    jmp     .aligned
.p_smaller:
    neg     rcx
    fmaf64_shr128 r12, r13
    or      r13, r10
.aligned:
    mov     rax, r11
    shr     rax, 1
    xor     rax, r11
    test    al, 1
    jnz     .subtract
    add     r13, rdi
    adc     r12, r15            ; sign: that of x*y (bit 0)
    jmp     .round
.subtract:
    cmp     r12, r15
    jne     .ordered
    cmp     r13, rdi
.ordered:
    jae     .p_larger
    sub     rdi, r13
    sbb     r15, r12
    mov     r12, r15
    mov     r13, rdi
    shr     r11, 1              ; sign of z
    jmp     .nonzero_check
.p_larger:
    sub     r13, rdi
    sbb     r12, r15
.nonzero_check:
    mov     rax, r12
    or      rax, r13
    jnz     .round
    xorpd   xmm0, xmm0          ; exact cancellation: +0
    jmp     .out

.round:
    ; b = top bit of R, s = b - (p - 1), eL = e + s, raised to emin
    bsr     rcx, r12
    jz      .r_low
    add     ecx, 64
    jmp     .r_msb
.r_low:
    bsr     rcx, r13
.r_msb:
    lea     rbx, [r8 - 1]
    sub     rcx, rbx            ; s
    lea     rbx, [rsi + rcx]    ; eL
    cmp     rbx, r9
    jge     .exp_ok
    mov     rax, r9
    sub     rax, rbx
    add     rcx, rax            ; s += emin - eL
    mov     rbx, r9
.exp_ok:
    test    rcx, rcx
    jg      .shift_round
    neg     rcx                 ; R is short: shift left, exact
    shl     r13, cl
    mov     rax, r13
    jmp     .build
.shift_round:
    dec     rcx                 ; keep the rounding bit: T = R >> (s - 1)
    fmaf64_shr128 r12, r13      ; r10 = sticky below the rounding bit
    mov     rax, r13
    shr     rax, 1              ; m
    test    r13, 1
    jz      .build              ; rounding bit 0: round down
    test    r10, r10
    jnz     .up
    test    rax, 1
    jz      .build              ; exact half, even: stay
.up:
    inc     rax
.build:
    cvtsi2sd xmm0, rax          ; exact (m <= 2^p)
    mov     rdi, rbx
    call    umath_scalbn_f64    ; exact, or overflow to Inf
    test    r11, 1
    jz      .out
    movq    rax, xmm0
    bts     rax, 63
    movq    xmm0, rax
.out:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; fmaf64__special - internal: CF=1 with xmm0 = result when an operand is
;                   special (non-finite, or a zero x, y or z)
; args:    xmm0 = x, xmm1 = y, xmm2 = z (doubles)
; -----------------------------------------------------------------------------
fmaf64__special:
    mov     rcx, [rel fmaf64_exp_mask]
    movq    rax, xmm0
    and     rax, rcx
    cmp     rax, rcx
    je      .plain              ; x not finite
    movq    rax, xmm1
    and     rax, rcx
    cmp     rax, rcx
    je      .plain              ; y not finite
    movq    rax, xmm2
    and     rax, rcx
    cmp     rax, rcx
    je      .z_special          ; finite x, y with Inf/NaN z
    movq    rax, xmm0
    add     rax, rax
    jz      .plain              ; x = +-0
    movq    rax, xmm1
    add     rax, rax
    jz      .plain              ; y = +-0
    movq    rax, xmm2
    add     rax, rax
    jz      .product            ; z = +-0: one rounding of x*y
    clc
    ret
.product:
    mulsd   xmm0, xmm1          ; x*y rounded once, z ignored: the exact
    stc                         ; product is nonzero, so its sign decides
    ret                         ; even when it underflows (x*y + +0 would
                                ; turn an underflowed -0 into +0)
.z_special:
    movapd  xmm0, xmm2
    addsd   xmm0, xmm2          ; z itself, NaN quieted
    stc
    ret
.plain:
    mulsd   xmm0, xmm1
    addsd   xmm0, xmm2
    stc
    ret

; -----------------------------------------------------------------------------
; umath_fma_f64 - x*y + z with a single rounding
; args:    xmm0 = x, xmm1 = y, xmm2 = z
; returns: xmm0 = fma(x, y, z)
; -----------------------------------------------------------------------------
global umath_fma_f64
umath_fma_f64:
    um_need umath__has_fma, .software
    vfmadd213sd xmm0, xmm1, xmm2
    ret
.software:
    call    fmaf64__special
    jc      .done
    mov     r8d, 53
    mov     r9, -1074
    call    fmaf64__core
.done:
    ret

; -----------------------------------------------------------------------------
; umath_fma_f32 - x*y + z with a single rounding (floats)
; args:    xmm0 = x, xmm1 = y, xmm2 = z (f32)
; returns: xmm0 = fma(x, y, z) (f32)
; Without FMA3 the operands are widened (exact) and the core rounds
; straight to 24 bits, so the float result is rounded only once.
; -----------------------------------------------------------------------------
global umath_fma_f32
umath_fma_f32:
    um_need umath__has_fma, .software
    vfmadd213ss xmm0, xmm1, xmm2
    ret
.software:
    cvtss2sd xmm0, xmm0
    cvtss2sd xmm1, xmm1
    cvtss2sd xmm2, xmm2
    call    fmaf64__special     ; its x*y is exact in double here
    jc      .narrow
    mov     r8d, 24
    mov     r9, -149
    call    fmaf64__core
.narrow:
    cvtsd2ss xmm0, xmm0         ; exact after the core; one rounding else
    ret

%endif ; GUARD_LIB_UMATH_MATH_FN_FMA_F64_ASM
