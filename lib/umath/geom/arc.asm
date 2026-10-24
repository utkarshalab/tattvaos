%ifndef GUARD_LIB_UMATH_GEOM_ARC_ASM
%define GUARD_LIB_UMATH_GEOM_ARC_ASM
; =============================================================================
; umath - unified math library
; geom/arc.asm - elliptical arcs as cubic Beziers (f64)
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; An axis-aligned elliptical arc is centre (cx, cy), radii (rx, ry), start
; angle and signed sweep in radians; the point at angle a is
; (cx + rx cos a, cy + ry sin a). The arc is split into n = ceil(|sweep| /
; (pi / 2)) equal pieces, each approximated by the cubic with handles of
; length k = 4/3 tan(theta / 4) along the tangents (radial error below
; 0.03% of the radius for a quarter turn). Sweeps are clamped to one full
; turn either way.
; =============================================================================

bits 64

%include "lib/umath/math_fn/sin_f64.asm"
%include "lib/umath/math_fn/cos_f64.asm"
%include "lib/umath/math_fn/tan_f64.asm"

section .rodata
align 8
arc_two_pi:         dq 6.283185307179586
arc_neg_two_pi:     dq -6.283185307179586
arc_half_pi:        dq 1.5707963267948966
arc_four_thirds:    dq 1.3333333333333333
arc_quarter:        dq 0.25

section .text

; -----------------------------------------------------------------------------
; (x, y) = umath_arc_point(double cx, double cy, double rx, double ry,
;                          double angle)
; -----------------------------------------------------------------------------
global umath_arc_point
umath_arc_point:
    sub rsp, 56
    movsd [rsp], xmm0
    movsd [rsp + 8], xmm1
    movsd [rsp + 16], xmm2
    movsd [rsp + 24], xmm3
    movsd [rsp + 32], xmm4
    movapd xmm0, xmm4
    call umath_cos_f64
    mulsd xmm0, [rsp + 16]
    addsd xmm0, [rsp]
    movsd [rsp + 40], xmm0              ; x
    movsd xmm0, [rsp + 32]
    call umath_sin_f64
    mulsd xmm0, [rsp + 24]
    addsd xmm0, [rsp + 8]
    movapd xmm1, xmm0                   ; y
    movsd xmm0, [rsp + 40]
    add rsp, 56
    ret

; -----------------------------------------------------------------------------
; size_t umath_arc_to_cubics(double out[24], double cx, double cy, double rx,
;                            double ry, double start, double sweep)
;   Writes n cubic pieces as (c1, c2, end) point triples, 6 doubles each;
;   the arc's start point is not written (see umath_arc_point). n is 0 for a
;   zero or non-finite sweep and at most 4.
; -----------------------------------------------------------------------------
%define ARC_CX      0
%define ARC_CY      8
%define ARC_RX      16
%define ARC_RY      24
%define ARC_A       32                  ; current angle
%define ARC_STEP    40
%define ARC_K       48
%define ARC_COS0    56
%define ARC_SIN0    64
%define ARC_COS1    72
%define ARC_SIN1    80
%define ARC_FRAME   88

global umath_arc_to_cubics
umath_arc_to_cubics:
    push rbx
    push r12
    push r13
    sub rsp, ARC_FRAME + 8              ; keeps rsp 16-byte aligned for calls
    mov rbx, rdi
    movsd [rsp + ARC_CX], xmm0
    movsd [rsp + ARC_CY], xmm1
    movsd [rsp + ARC_RX], xmm2
    movsd [rsp + ARC_RY], xmm3
    movsd [rsp + ARC_A], xmm4
    ; clamp the sweep to one turn; reject zero and NaN
    xorpd xmm6, xmm6
    ucomisd xmm5, xmm6
    jp .none
    je .none
    minsd xmm5, [rel arc_two_pi]
    maxsd xmm5, [rel arc_neg_two_pi]
    ; n = ceil(|sweep| / (pi / 2)), 1..4
    movapd xmm7, xmm5
    xorpd xmm6, xmm6
    subsd xmm6, xmm7
    maxsd xmm7, xmm6                    ; |sweep|
    divsd xmm7, [rel arc_half_pi]
    cvttsd2si r12, xmm7
    cvtsi2sd xmm6, r12
    ucomisd xmm6, xmm7
    jae .count_ready
    inc r12
.count_ready:
    test r12, r12
    jnz .count_nonzero
    mov r12d, 1
.count_nonzero:
    cmp r12, 4
    jbe .count_ok
    mov r12d, 4
.count_ok:
    cvtsi2sd xmm6, r12
    divsd xmm5, xmm6
    movsd [rsp + ARC_STEP], xmm5        ; theta per piece
    ; k = 4/3 tan(theta / 4)
    movapd xmm0, xmm5
    mulsd xmm0, [rel arc_quarter]
    call umath_tan_f64
    mulsd xmm0, [rel arc_four_thirds]
    movsd [rsp + ARC_K], xmm0
    movsd xmm0, [rsp + ARC_A]
    call umath_cos_f64
    movsd [rsp + ARC_COS0], xmm0
    movsd xmm0, [rsp + ARC_A]
    call umath_sin_f64
    movsd [rsp + ARC_SIN0], xmm0
    xor r13d, r13d
.piece:
    movsd xmm0, [rsp + ARC_A]
    addsd xmm0, [rsp + ARC_STEP]
    movsd [rsp + ARC_A], xmm0
    call umath_cos_f64
    movsd [rsp + ARC_COS1], xmm0
    movsd xmm0, [rsp + ARC_A]
    call umath_sin_f64
    movsd [rsp + ARC_SIN1], xmm0
    ; c1 = p0 + k * (-rx sin0, ry cos0)
    movsd xmm2, [rsp + ARC_K]
    movsd xmm0, [rsp + ARC_COS0]
    movsd xmm1, [rsp + ARC_SIN0]
    movapd xmm3, xmm1
    mulsd xmm3, xmm2
    subsd xmm0, xmm3                    ; cos0 - k sin0
    mulsd xmm0, [rsp + ARC_RX]
    addsd xmm0, [rsp + ARC_CX]
    movsd [rbx], xmm0
    movsd xmm0, [rsp + ARC_COS0]
    mulsd xmm0, xmm2
    addsd xmm0, xmm1                    ; sin0 + k cos0
    mulsd xmm0, [rsp + ARC_RY]
    addsd xmm0, [rsp + ARC_CY]
    movsd [rbx + 8], xmm0
    ; c2 = p1 - k * (-rx sin1, ry cos1)
    movsd xmm0, [rsp + ARC_SIN1]
    mulsd xmm0, xmm2
    addsd xmm0, [rsp + ARC_COS1]        ; cos1 + k sin1
    mulsd xmm0, [rsp + ARC_RX]
    addsd xmm0, [rsp + ARC_CX]
    movsd [rbx + 16], xmm0
    movsd xmm0, [rsp + ARC_COS1]
    mulsd xmm0, xmm2
    movsd xmm1, [rsp + ARC_SIN1]
    subsd xmm1, xmm0                    ; sin1 - k cos1
    mulsd xmm1, [rsp + ARC_RY]
    addsd xmm1, [rsp + ARC_CY]
    movsd [rbx + 24], xmm1
    ; end point
    movsd xmm0, [rsp + ARC_COS1]
    mulsd xmm0, [rsp + ARC_RX]
    addsd xmm0, [rsp + ARC_CX]
    movsd [rbx + 32], xmm0
    movsd xmm0, [rsp + ARC_SIN1]
    mulsd xmm0, [rsp + ARC_RY]
    addsd xmm0, [rsp + ARC_CY]
    movsd [rbx + 40], xmm0
    ; the end becomes the next start
    movsd xmm0, [rsp + ARC_COS1]
    movsd [rsp + ARC_COS0], xmm0
    movsd xmm0, [rsp + ARC_SIN1]
    movsd [rsp + ARC_SIN0], xmm0
    add rbx, 48
    inc r13
    cmp r13, r12
    jb .piece
    mov rax, r12
    add rsp, ARC_FRAME + 8
    pop r13
    pop r12
    pop rbx
    ret
.none:
    xor eax, eax
    add rsp, ARC_FRAME + 8
    pop r13
    pop r12
    pop rbx
    ret

%endif ; GUARD_LIB_UMATH_GEOM_ARC_ASM
