%ifndef GUARD_LIB_UMATH_GEOM_ARC_ASM
%define GUARD_LIB_UMATH_GEOM_ARC_ASM
; =============================================================================
; umath - unified math library
; geom/arc.asm - elliptical arcs as cubic Beziers (f64), axis-aligned by
;                 centre and angles, or SVG-style by end points
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
%include "lib/umath/math_fn/atan2_f64.asm"

section .rodata
align 8
arc_two_pi:         dq 6.283185307179586
arc_neg_two_pi:     dq -6.283185307179586
arc_half_pi:        dq 1.5707963267948966
arc_four_thirds:    dq 1.3333333333333333
arc_quarter:        dq 0.25
arc_half:           dq 0.5
arc_one:            dq 1.0

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

; -----------------------------------------------------------------------------
; size_t umath_arc_svg_to_cubics(double out[24], double x1, double y1,
;                                double x2, double y2, double rx, double ry,
;                                double phi, int flags)
;   An SVG elliptical arc from (x1, y1) to (x2, y2): radii rx, ry, x-axis
;   rotation phi (radians), flags bit 0 = large-arc, bit 1 = sweep. Writes n
;   cubics like umath_arc_to_cubics (the start point not written; the last
;   end point is exactly (x2, y2)). Follows SVG 1.1 F.6.5-F.6.6: radii are
;   taken as |rx|, |ry| and scaled up when too small to reach (the centre is
;   then exactly the chord's midpoint); a zero radius
;   gives one straight cubic; equal end points give n = 0.
; -----------------------------------------------------------------------------
%define SA_X1       0
%define SA_Y1       8
%define SA_X2       16
%define SA_Y2       24
%define SA_RX       32
%define SA_RY       40
%define SA_COS      48
%define SA_SIN      56
%define SA_XP       64                  ; x1', y1'
%define SA_YP       72
%define SA_CXP      80                  ; cx', cy'
%define SA_CYP      88
%define SA_CX       96
%define SA_CY       104
%define SA_T1       112
%define SA_PHI      120
%define SA_FLAGS    128
%define SA_N        136
%define SA_FRAME    144

global umath_arc_svg_to_cubics
umath_arc_svg_to_cubics:
    push rbx
    sub rsp, SA_FRAME
    mov rbx, rdi
    movsd [rsp + SA_X1], xmm0
    movsd [rsp + SA_Y1], xmm1
    movsd [rsp + SA_X2], xmm2
    movsd [rsp + SA_Y2], xmm3
    movsd [rsp + SA_PHI], xmm6
    mov [rsp + SA_FLAGS], esi
    ; equal end points: nothing
    ucomisd xmm0, xmm2
    jne .sa_apart
    jp .sa_apart
    ucomisd xmm1, xmm3
    jne .sa_apart
    jp .sa_apart
    xor eax, eax
    jmp .sa_out
.sa_apart:
    andpd xmm4, [rel arc_abs_mask]
    andpd xmm5, [rel arc_abs_mask]
    movsd [rsp + SA_RX], xmm4
    movsd [rsp + SA_RY], xmm5
    xorpd xmm7, xmm7
    ucomisd xmm4, xmm7
    jp .sa_line
    je .sa_line
    ucomisd xmm5, xmm7
    jp .sa_line
    je .sa_line
    movsd xmm0, [rsp + SA_PHI]
    call umath_cos_f64
    movsd [rsp + SA_COS], xmm0
    movsd xmm0, [rsp + SA_PHI]
    call umath_sin_f64
    movsd [rsp + SA_SIN], xmm0
    ; (x1', y1') = R(-phi) ((p1 - p2) / 2)
    movsd xmm0, [rsp + SA_X1]
    subsd xmm0, [rsp + SA_X2]
    mulsd xmm0, [rel arc_half]          ; dx
    movsd xmm1, [rsp + SA_Y1]
    subsd xmm1, [rsp + SA_Y2]
    mulsd xmm1, [rel arc_half]          ; dy
    movsd xmm2, [rsp + SA_COS]
    mulsd xmm2, xmm0
    movsd xmm3, [rsp + SA_SIN]
    mulsd xmm3, xmm1
    addsd xmm2, xmm3
    movsd [rsp + SA_XP], xmm2
    movsd xmm2, [rsp + SA_COS]
    mulsd xmm2, xmm1
    movsd xmm3, [rsp + SA_SIN]
    mulsd xmm3, xmm0
    subsd xmm2, xmm3
    movsd [rsp + SA_YP], xmm2
    ; lambda = x1'^2 / rx^2 + y1'^2 / ry^2 > 1: scale the radii by sqrt
    movsd xmm0, [rsp + SA_XP]
    divsd xmm0, [rsp + SA_RX]
    mulsd xmm0, xmm0
    movsd xmm1, [rsp + SA_YP]
    divsd xmm1, [rsp + SA_RY]
    mulsd xmm1, xmm1
    addsd xmm0, xmm1
    mov dword [rsp + SA_N], 0           ; 1: radii scaled (centre = midpoint)
    ucomisd xmm0, [rel arc_one]
    jbe .sa_radii_ok
    mov dword [rsp + SA_N], 1
    sqrtsd xmm0, xmm0
    movsd xmm1, [rsp + SA_RX]
    mulsd xmm1, xmm0
    movsd [rsp + SA_RX], xmm1
    movsd xmm1, [rsp + SA_RY]
    mulsd xmm1, xmm0
    movsd [rsp + SA_RY], xmm1
.sa_radii_ok:
    ; coef = +-sqrt(max(0, (rx^2 ry^2 - rx^2 y1'^2 - ry^2 x1'^2) /
    ;                       (rx^2 y1'^2 + ry^2 x1'^2))), - when large == sweep
    movsd xmm0, [rsp + SA_RX]
    mulsd xmm0, xmm0                    ; rx^2
    movsd xmm1, [rsp + SA_RY]
    mulsd xmm1, xmm1                    ; ry^2
    movsd xmm2, [rsp + SA_YP]
    mulsd xmm2, xmm2
    mulsd xmm2, xmm0                    ; rx^2 y1'^2
    movsd xmm3, [rsp + SA_XP]
    mulsd xmm3, xmm3
    mulsd xmm3, xmm1                    ; ry^2 x1'^2
    movapd xmm4, xmm0
    mulsd xmm4, xmm1
    subsd xmm4, xmm2
    subsd xmm4, xmm3                    ; numerator
    addsd xmm2, xmm3                    ; denominator (> 0: the points differ)
    divsd xmm4, xmm2
    xorpd xmm5, xmm5
    maxsd xmm4, xmm5
    sqrtsd xmm4, xmm4
    cmp dword [rsp + SA_N], 0
    je .sa_coef_ok
    xorpd xmm4, xmm4                    ; scaled radii: exactly 0, not rounding noise
.sa_coef_ok:
    mov eax, [rsp + SA_FLAGS]
    mov ecx, eax
    shr ecx, 1
    xor eax, ecx
    test eax, 1
    jnz .sa_sign_ok                     ; large != sweep: +
    xorpd xmm5, xmm5
    subsd xmm5, xmm4
    movapd xmm4, xmm5
.sa_sign_ok:
    ; (cx', cy') = coef (rx y1' / ry, -ry x1' / rx)
    movsd xmm0, [rsp + SA_RX]
    mulsd xmm0, [rsp + SA_YP]
    divsd xmm0, [rsp + SA_RY]
    mulsd xmm0, xmm4
    movsd [rsp + SA_CXP], xmm0
    movsd xmm0, [rsp + SA_RY]
    mulsd xmm0, [rsp + SA_XP]
    divsd xmm0, [rsp + SA_RX]
    mulsd xmm0, xmm4
    xorpd xmm1, xmm1
    subsd xmm1, xmm0
    movsd [rsp + SA_CYP], xmm1
    ; centre = R(phi) c' + (p1 + p2) / 2
    movsd xmm0, [rsp + SA_COS]
    mulsd xmm0, [rsp + SA_CXP]
    movsd xmm1, [rsp + SA_SIN]
    mulsd xmm1, [rsp + SA_CYP]
    subsd xmm0, xmm1
    movsd xmm1, [rsp + SA_X1]
    addsd xmm1, [rsp + SA_X2]
    mulsd xmm1, [rel arc_half]
    addsd xmm0, xmm1
    movsd [rsp + SA_CX], xmm0
    movsd xmm0, [rsp + SA_SIN]
    mulsd xmm0, [rsp + SA_CXP]
    movsd xmm1, [rsp + SA_COS]
    mulsd xmm1, [rsp + SA_CYP]
    addsd xmm0, xmm1
    movsd xmm1, [rsp + SA_Y1]
    addsd xmm1, [rsp + SA_Y2]
    mulsd xmm1, [rel arc_half]
    addsd xmm0, xmm1
    movsd [rsp + SA_CY], xmm0
    ; theta1 = angle of u = ((x1' - cx') / rx, (y1' - cy') / ry)
    movsd xmm0, [rsp + SA_YP]
    subsd xmm0, [rsp + SA_CYP]
    divsd xmm0, [rsp + SA_RY]           ; uy
    movsd xmm1, [rsp + SA_XP]
    subsd xmm1, [rsp + SA_CXP]
    divsd xmm1, [rsp + SA_RX]           ; ux
    call umath_atan2_f64
    movsd [rsp + SA_T1], xmm0
    ; dtheta = angle from u to v = ((-x1' - cx') / rx, (-y1' - cy') / ry)
    movsd xmm2, [rsp + SA_XP]
    subsd xmm2, [rsp + SA_CXP]
    divsd xmm2, [rsp + SA_RX]           ; ux
    movsd xmm3, [rsp + SA_YP]
    subsd xmm3, [rsp + SA_CYP]
    divsd xmm3, [rsp + SA_RY]           ; uy
    xorpd xmm4, xmm4
    subsd xmm4, [rsp + SA_XP]
    subsd xmm4, [rsp + SA_CXP]
    divsd xmm4, [rsp + SA_RX]           ; vx
    xorpd xmm5, xmm5
    subsd xmm5, [rsp + SA_YP]
    subsd xmm5, [rsp + SA_CYP]
    divsd xmm5, [rsp + SA_RY]           ; vy
    movapd xmm0, xmm2
    mulsd xmm0, xmm5
    movapd xmm6, xmm3
    mulsd xmm6, xmm4
    subsd xmm0, xmm6                    ; u x v
    movapd xmm1, xmm2
    mulsd xmm1, xmm4
    movapd xmm6, xmm3
    mulsd xmm6, xmm5
    addsd xmm1, xmm6                    ; u . v
    call umath_atan2_f64
    ; sweep 0: dtheta <= 0; sweep 1: dtheta >= 0
    xorpd xmm1, xmm1
    test dword [rsp + SA_FLAGS], 2
    jz .sa_negative
    ucomisd xmm0, xmm1
    jae .sa_have_sweep
    addsd xmm0, [rel arc_two_pi]
    jmp .sa_have_sweep
.sa_negative:
    ucomisd xmm0, xmm1
    jbe .sa_have_sweep
    subsd xmm0, [rel arc_two_pi]
.sa_have_sweep:
    movapd xmm5, xmm0
    mov rdi, rbx
    xorpd xmm0, xmm0
    xorpd xmm1, xmm1
    movsd xmm2, [rsp + SA_RX]
    movsd xmm3, [rsp + SA_RY]
    movsd xmm4, [rsp + SA_T1]
    call umath_arc_to_cubics
    mov [rsp + SA_N], rax
    ; rotate by phi and move to the centre
    lea rcx, [rax * 2 + rax]            ; 3 points per cubic
    xor edx, edx
.sa_point:
    cmp rdx, rcx
    jae .sa_pin
    mov r8, rdx
    shl r8, 4
    movsd xmm0, [rbx + r8]
    movsd xmm1, [rbx + r8 + 8]
    movsd xmm2, [rsp + SA_COS]
    mulsd xmm2, xmm0
    movsd xmm3, [rsp + SA_SIN]
    mulsd xmm3, xmm1
    subsd xmm2, xmm3
    addsd xmm2, [rsp + SA_CX]
    movsd xmm3, [rsp + SA_SIN]
    mulsd xmm3, xmm0
    movsd xmm4, [rsp + SA_COS]
    mulsd xmm4, xmm1
    addsd xmm3, xmm4
    addsd xmm3, [rsp + SA_CY]
    movsd [rbx + r8], xmm2
    movsd [rbx + r8 + 8], xmm3
    inc rdx
    jmp .sa_point
.sa_pin:
    mov rax, [rsp + SA_N]
    test rax, rax
    jz .sa_out
    imul rcx, rax, 48
    movsd xmm0, [rsp + SA_X2]
    movsd [rbx + rcx - 16], xmm0
    movsd xmm0, [rsp + SA_Y2]
    movsd [rbx + rcx - 8], xmm0
    jmp .sa_out
.sa_line:
    ; a zero radius: one straight cubic, handles at the end points
    movsd xmm0, [rsp + SA_X1]
    movsd [rbx], xmm0
    movsd xmm0, [rsp + SA_Y1]
    movsd [rbx + 8], xmm0
    movsd xmm0, [rsp + SA_X2]
    movsd [rbx + 16], xmm0
    movsd [rbx + 32], xmm0
    movsd xmm0, [rsp + SA_Y2]
    movsd [rbx + 24], xmm0
    movsd [rbx + 40], xmm0
    mov eax, 1
.sa_out:
    add rsp, SA_FRAME
    pop rbx
    ret

section .rodata
align 16
arc_abs_mask:       dq 0x7FFFFFFFFFFFFFFF, 0x7FFFFFFFFFFFFFFF
section .text

%endif ; GUARD_LIB_UMATH_GEOM_ARC_ASM
