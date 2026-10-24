%ifndef GUARD_LIB_UMATH_MATH_FN_GAMMA_F64_ASM
%define GUARD_LIB_UMATH_MATH_FN_GAMMA_F64_ASM
; =============================================================================
; umath - unified math library
; math_fn/gamma_f64.asm - gamma function and its logarithm
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
;   umath_tgamma_f64(x)           Gamma(x)
;   umath_lgamma_f64(x)           ln|Gamma(x)|
;   umath_lgamma_r_f64(x, *sign)  ln|Gamma(x)|, and the sign of Gamma(x)
;                                 (+1 / -1, int32) stored to *sign
;
; Kernel: Gamma(1 + t) = 1 + t*G(t) on t in [-0.5, 0.5], with
; G(t) = (Gamma(1+t) - 1)/t fitted for this file (Chebyshev, mpmath, 60
; digits) on [-0.5, 0] (degree 23) and [0, 0.5] (degree 17), each centred,
; within 2.4e-16 relative in double. G has no zero on [-0.5, 0.5], so the
; form keeps full relative accuracy for both Gamma and its logarithm.
;
; tgamma, x > 0:
;   x < 2^-54     1/x
;   x < 0.5       (1 + x*G(x)) / x                    (x itself is exact)
;   x >= 0.5      x = n + f, f in [0.5, 1.5): Gamma(f) from the kernel, then
;                 times (x-n) (x-n+1) ... (x-1). Every factor x - j is exact,
;                 and the running product is kept as a double-double (Dekker
;                 product, no FMA needed), rescaled by 2^-500 whenever it
;                 passes 2^500, so up to 170 multiplications round once at
;                 the end. Overflow from x ~ 171.6244 on.
; tgamma, x < 0 (non-integer): Gamma(x) = -pi / (x sin(pi x) Gamma(-x)),
;   sin(pi x) from an exact reduction of x to [-1/2, 1/2] (x - 2 round(x/2),
;   then 1 - r), and Gamma(-x) in its scaled form, so results that are
;   subnormal (down to x ~ -184) come out right instead of 0. Negative
;   integers give NaN, -Inf NaN, +-0 give +-Inf.
;
; lgamma, x > 0 (each form exact at the zeros x = 1 and x = 2):
;   x < 2^-54     -ln x
;   x < 0.5       log1p(x*G(x)) - ln x
;   x < 3         (x - 1)(x - 2) K(x), K = lgamma(x)/((x-1)(x-2)) fitted
;                 on [0.5,1], [1,2], [2,3] (degrees 22, 22, 20): K is smooth
;                 and has no zero there, and the factors vanish exactly at
;                 lgamma's zeros, so the relative accuracy holds right
;                 through x = 1 and x = 2 (3e-16 in double)
;   x < 4         the same at x - 1, plus ln(x - 1) (both positive)
;   x < 171       ln M + k ln2 from the scaled Gamma
;   otherwise     Stirling: (x - 1/2)(ln x - 1) + (ln(2 pi) - 1)/2
;                 + 1/(12x) - 1/(360x^3) + 1/(1260x^5) - 1/(1680x^7)
; lgamma, x < 0 (non-integer): ln pi - ln|x sin(pi x)| - lgamma(-x); poles
;   (0 and negative integers) and +-Inf give +Inf. Close to the points where
;   |Gamma(x)| = 1 on the negative axis the reflection cancels, as in every
;   libm, and the relative error grows there.
; =============================================================================

bits 64

%include "lib/umath/math_fn/log_f64.asm"
%include "lib/umath/math_fn/log1p_f64.asm"
%include "lib/umath/math_fn/sin_f64.asm"
%include "lib/umath/math_fn/scalbn_f64.asm"
%include "lib/umath/math_fn/polyval.asm"
%include "lib/umath/math_fn/loops.asm"
%include "lib/umath/cpuid/fallback.asm"

section .rodata
align 8
gamf64_one:         dq 1.0
gamf64_half:        dq 0.5
gamf64_two:         dq 2.0
gamf64_171:         dq 171.0
gamf64_172:         dq 172.0
gamf64_m200:        dq -200.0
gamf64_tiny:        dq 0x3C90000000000000       ; 2^-54
gamf64_big_int:     dq 0x4330000000000000       ; 2^52
gamf64_2p500:       dq 0x5F30000000000000       ; 2^500
gamf64_2m500:       dq 0x20B0000000000000       ; 2^-500
gamf64_split:       dq 134217729.0
gamf64_pi:          dq 0x400921FB54442D18
gamf64_ln_pi:       dq 1.1447298858494002
gamf64_ln2_hi:      dq 0x3FE62E42FEE00000
gamf64_ln2_lo:      dq 0x3DEA39EF35793C76
gamf64_stirling_c:  dq 0.4189385332046727        ; (ln(2 pi) - 1)/2
gamf64_s1:          dq 0.08333333333333333       ; 1/12
gamf64_s3:          dq 0.002777777777777778      ; 1/360
gamf64_s5:          dq 0.0007936507936507937     ; 1/1260
gamf64_s7:          dq 0.0005952380952380953     ; 1/1680
gamf64_inf:         dq 0x7FF0000000000000
gamf64_nan:         dq 0x7FF8000000000000
gamf64_c_neg:       dq -0.25
gamf64_c_pos:       dq 0.25
gamf64_k_neg:       ; G on [-0.5, 0], s = t + 0.25, 24 coefficients
    dq 0x409F3E1960CB97F9, 0xC0976E930860EC28, 0x40776E93066AF86D
    dq 0xC07192EE4278AECD, 0x4074DE7AEC936E4A, 0xC06F4DB85469A7FC
    dq 0x40660748B8A7FB8F, 0xC06085765E4032FA, 0x4058F489B7D23B64
    dq 0xC052B7663AF6B120, 0x404C0F955F154EE9, 0xC0450BA98D2DFA56
    dq 0x403F9196DFBE06F1, 0xC037AD098B2364A7, 0x4031C1813499B1D5
    dq 0xC02AA14F9F8244AD, 0x4023F75A3D03A41F, 0xC01DED2C285A9988
    dq 0x4016689AAF4212EC, 0xC010BAAC25CC52B4, 0x4008F2676FFBE57D
    dq 0xC0020C5FD5EE981E, 0x3FFB742AA8A93A85, 0xBFECDA745A87B160
gamf64_k_pos:       ; G on [0, 0.5], s = t - 0.25, 18 coefficients
    dq 0x3F9625454B331594, 0xBF9BAE8662F60236, 0x3F9C5F87FDC618A0
    dq 0xBFA1BB8E39F4AE21, 0x3FA68787EA661807, 0xBFAC28A57EFF2C52
    dq 0x3FB195986C41E852, 0xBFB5F90A2B4AA399, 0x3FBB7337F4347917
    dq 0xBFC122C67A200081, 0x3FC562ADDFCB98C8, 0xBFCA996366CFBF6B
    dq 0x3FD09B1CCB94995C, 0xBFD42E057DE0ECC8, 0x3FD9FD5286B81E3C
    dq 0xBFDB58E3F728AB8D, 0x3FE5886AFF5696A4, 0xBFD7F601DC0888AE

gamf64_k1_c:   dq 0x3FE8000000000000
gamf64_k1:   ; 23 coefficients
    dq 0x40365E12FBE4B75B, 0xC0317E9DF424F33E, 0x4016AE71C3B2CE20
    dq 0xC011E81EECDA0A26, 0x401332F8CAB8FC47, 0xC00E5E43B271A31C
    dq 0x400731C293EE9C94, 0xC00278F8F049F8EA, 0x3FFDA30170CF9871
    dq 0xBFF7CB79ABEAE914, 0x3FF33227C59A1540, 0xBFEF280954547396
    dq 0x3FE974A0B5C739AA, 0xBFE4F701EE59A506, 0x3FE16F3FE0A5EA0E
    dq 0xBFDD592180852FFF, 0x3FD915A51B26F66E, 0xBFD5E2FBAD66D1E7
    dq 0x3FD3AA2BB20327DF, 0xBFD27D8568C43728, 0x3FD2D24B6E9D82E2
    dq 0xBFD68D0E724A2F56, 0x3FE4D0E35F51A18B
gamf64_k2_c:   dq 0x3FF8000000000000
gamf64_k2:   ; 23 coefficients
    dq 0x3ED5690AC55F96FC, 0xBEE0B7547CBEF874, 0x3ED5841C8F950E54
    dq 0xBEE0F1AA0B730E2E, 0x3EF22F60FF768E29, 0xBEFCAF7091C01F9B
    dq 0x3F05D42C628EDBEC, 0xBF1153682EA04D6A, 0x3F1BB1B2F70EDA70
    dq 0xBF2624418C291D11, 0x3F31C73D7BB3879A, 0xBF3CB449093F4D2B
    dq 0x3F4750AEAFCE189C, 0xBF5313E8BBBF0A5C, 0x3F5F814B7A8EA944
    dq 0xBF6A5035229E81B4, 0x3F764F066526297D, 0xBF834DBDA14A534E
    dq 0x3F91334235278E97, 0xBFA007AA83CEE106, 0x3FB01AF62A2929E8
    dq 0xBFC2AED059BD608A, 0x3FDEEB95B094C191
gamf64_k3_c:   dq 0x4004000000000000
gamf64_k3:   ; 21 coefficients
    dq 0x3DF37D391D4927B2, 0xBE096EAC886941B7, 0x3E1ADC1411CC02D9
    dq 0xBE319E00A4BCB2AD, 0x3E479E92BD8D495F, 0xBE5F25CB9E87E576
    dq 0x3E74965094B54CA9, 0xBE8B57209DC0783C, 0x3EA23BDDA778FCE1
    dq 0xBEB871ED62EB9035, 0x3ED07C7681E3870C, 0xBEE66707FDB1C369
    dq 0x3EFEB8F744B9B175, 0xBF15501AAFF57926, 0x3F2E05C3C3C02141
    dq 0xBF459512000E3FAA, 0x3F5FEEF08B132012, 0xBF78A722DFC5D7FF
    dq 0x3F9462044B0AF671, 0xBFB31D26E9323010, 0x3FD84AFE00CDDFDF
gamf64_three:       dq 3.0
gamf64_four:        dq 4.0

section .text

; -----------------------------------------------------------------------------
; gamf64__G - internal: G(t) for t in [-0.5, 0.5]
; args: xmm0 = t; returns xmm0 = G(t). Clobbers xmm1, xmm2.
; -----------------------------------------------------------------------------
gamf64__G:
    xorpd   xmm2, xmm2
    comisd  xmm0, xmm2
    jb      .neg
    movapd  xmm1, xmm0
    subsd   xmm1, [rel gamf64_c_pos]
    mathfn_horner gamf64_k_pos, 18, xmm1, xmm2
    movapd  xmm0, xmm2
    ret
.neg:
    movapd  xmm1, xmm0
    subsd   xmm1, [rel gamf64_c_neg]
    mathfn_horner gamf64_k_neg, 24, xmm1, xmm2
    movapd  xmm0, xmm2
    ret

; -----------------------------------------------------------------------------
; gamf64__scaled - internal: Gamma(x) = M * 2^k for 0 < x < 200
; args: xmm0 = x; returns xmm0 = M, rax = k (a multiple of 500, usually 0)
; Clobbers rcx, xmm1-xmm9.
; -----------------------------------------------------------------------------
gamf64__scaled:
    comisd  xmm0, [rel gamf64_half]
    jae     .not_small
    ; x < 0.5: (1 + x*G(x)) / x
    movapd  xmm7, xmm0
    call    gamf64__G
    mulsd   xmm0, xmm7
    addsd   xmm0, [rel gamf64_one]
    divsd   xmm0, xmm7
    xor     eax, eax
    ret
.not_small:
    movapd  xmm7, xmm0          ; x
    movapd  xmm1, xmm0
    subsd   xmm1, [rel gamf64_half]
    cvttsd2si rcx, xmm1         ; n = floor(x - 0.5) (x - 0.5 > 0)
    cvtsi2sd xmm1, rcx
    movapd  xmm0, xmm7
    subsd   xmm0, xmm1          ; f = x - n, exact, in [0.5, 1.5)
    subsd   xmm0, [rel gamf64_one]  ; t = f - 1, exact
    movapd  xmm6, xmm0
    call    gamf64__G
    mulsd   xmm0, xmm6
    addsd   xmm0, [rel gamf64_one]  ; ph = Gamma(f)
    xorpd   xmm6, xmm6          ; pl
    xor     eax, eax            ; k
.mul:
    test    rcx, rcx
    jz      .finish
    cvtsi2sd xmm1, rcx
    movapd  xmm5, xmm7
    subsd   xmm5, xmm1          ; c = x - j, exact (j = n .. 1)
    ; p = ph*c exactly as p + e (Dekker)
    movapd  xmm1, xmm0
    mulsd   xmm1, xmm5          ; p
    movsd   xmm2, [rel gamf64_split]
    mulsd   xmm2, xmm0
    movapd  xmm3, xmm2
    subsd   xmm3, xmm0
    subsd   xmm2, xmm3          ; ph_hi
    movapd  xmm3, xmm0
    subsd   xmm3, xmm2          ; ph_lo
    movsd   xmm4, [rel gamf64_split]
    mulsd   xmm4, xmm5
    movapd  xmm0, xmm4
    subsd   xmm0, xmm5
    subsd   xmm4, xmm0          ; c_hi
    movapd  xmm0, xmm5
    subsd   xmm0, xmm4          ; c_lo
    ; e = ((ph_hi*c_hi - p) + ph_hi*c_lo + ph_lo*c_hi) + ph_lo*c_lo
    movapd  xmm8, xmm2
    mulsd   xmm8, xmm4
    subsd   xmm8, xmm1
    movapd  xmm9, xmm2
    mulsd   xmm9, xmm0
    addsd   xmm8, xmm9
    movapd  xmm9, xmm3
    mulsd   xmm9, xmm4
    addsd   xmm8, xmm9
    mulsd   xmm3, xmm0
    addsd   xmm8, xmm3          ; e
    mulsd   xmm6, xmm5
    addsd   xmm6, xmm8          ; pl*c + e
    movapd  xmm0, xmm1
    addsd   xmm0, xmm6          ; s = p + pl
    movapd  xmm2, xmm0
    subsd   xmm2, xmm1
    subsd   xmm6, xmm2          ; pl = pl - (s - p)
    comisd  xmm0, [rel gamf64_2p500]
    jb      .next
    mulsd   xmm0, [rel gamf64_2m500]
    mulsd   xmm6, [rel gamf64_2m500]
    add     eax, 500
.next:
    dec     rcx
    jmp     .mul
.finish:
    addsd   xmm0, xmm6          ; M = ph + pl, one rounding
    ret

; -----------------------------------------------------------------------------
; gamf64__sinpi - internal: sin(pi x) for finite non-integer x
; args: xmm0 = x; returns xmm0 = sin(pi x). Clobbers what umath_sin_f64 does.
; -----------------------------------------------------------------------------
gamf64__sinpi:
    sub     rsp, 8
    movapd  xmm1, xmm0
    mulsd   xmm1, [rel gamf64_half]
    um_roundsd xmm1, xmm1, 0    ; round(x/2)
    addsd   xmm1, xmm1
    subsd   xmm0, xmm1          ; r = x - 2 round(x/2), exact, in [-1, 1]
    comisd  xmm0, [rel gamf64_half]
    jbe     .not_above
    movsd   xmm1, [rel gamf64_one]
    subsd   xmm1, xmm0          ; 1 - r, exact: sin(pi(1-r)) = sin(pi r)
    movapd  xmm0, xmm1
    jmp     .reduced
.not_above:
    movsd   xmm1, [rel gamf64_half]
    xorpd   xmm2, xmm2
    subsd   xmm2, xmm1          ; -0.5
    comisd  xmm0, xmm2
    jae     .reduced
    movsd   xmm1, [rel gamf64_one]
    addsd   xmm1, xmm0
    xorpd   xmm0, xmm0
    subsd   xmm0, xmm1          ; -1 - r, exact
.reduced:
    mulsd   xmm0, [rel gamf64_pi]
    call    umath_sin_f64
    add     rsp, 8
    ret

; -----------------------------------------------------------------------------
; gamf64__is_int - internal: ZF = 1 when finite xmm0 is an integer
; Clobbers xmm1.
; -----------------------------------------------------------------------------
gamf64__is_int:
    um_roundsd xmm1, xmm0, 3
    ucomisd xmm1, xmm0
    ret

; -----------------------------------------------------------------------------
; umath_tgamma_f64 - the gamma function
; args:    xmm0 = x
; returns: xmm0 = Gamma(x)
; -----------------------------------------------------------------------------
global umath_tgamma_f64
umath_tgamma_f64:
    ucomisd xmm0, xmm0
    jp      .nan
    xorpd   xmm1, xmm1
    ucomisd xmm0, xmm1
    je      .zero
    jb      .negative
    ucomisd xmm0, [rel gamf64_172]
    jae     .overflow           ; also +Inf
    comisd  xmm0, [rel gamf64_tiny]
    jb      .reciprocal
    sub     rsp, 8
    call    gamf64__scaled
    mov     rdi, rax
    call    umath_scalbn_f64
    add     rsp, 8
    ret
.reciprocal:
    movsd   xmm1, [rel gamf64_one]
    divsd   xmm1, xmm0          ; 1/x (Inf for the smallest subnormals)
    movapd  xmm0, xmm1
    ret
.zero:
    movsd   xmm1, [rel gamf64_one]
    divsd   xmm1, xmm0          ; +-Inf with the sign of the zero
    movapd  xmm0, xmm1
    ret
.overflow:
    movsd   xmm0, [rel gamf64_inf]
    ret
.negative:
    movq    rax, xmm0
    mov     rcx, 0xFFF0000000000000
    cmp     rax, rcx
    je      .invalid            ; -Inf
    call    gamf64__is_int
    je      .invalid            ; pole
    sub     rsp, 40
    movsd   [rsp], xmm0         ; x
    comisd  xmm0, [rel gamf64_m200]
    jb      .underflow
    call    gamf64__sinpi
    movsd   [rsp + 8], xmm0     ; sin(pi x)
    movsd   xmm0, [rsp]
    xorpd   xmm1, xmm1
    subsd   xmm1, xmm0
    movapd  xmm0, xmm1          ; -x > 0
    call    gamf64__scaled      ; Gamma(-x) = M * 2^k
    mov     [rsp + 16], rax
    movsd   xmm1, [rsp]
    mulsd   xmm1, [rsp + 8]     ; x sin(pi x)
    mulsd   xmm1, xmm0          ; * M
    movsd   xmm0, [rel gamf64_pi]
    divsd   xmm0, xmm1
    xorpd   xmm1, xmm1
    subsd   xmm1, xmm0          ; -pi / (x sin(pi x) M)
    movapd  xmm0, xmm1
    mov     rdi, [rsp + 16]
    neg     rdi
    call    umath_scalbn_f64    ; * 2^-k
    add     rsp, 40
    ret
.underflow:                     ; |Gamma(x)| < 1e-370: signed zero
    call    gamf64__sinpi       ; sign of Gamma(x) = sign of sin(pi x)
    movq    rax, xmm0
    shr     rax, 63
    shl     rax, 63
    movq    xmm0, rax
    add     rsp, 40
    ret
.invalid:
    movsd   xmm0, [rel gamf64_nan]
    ret
.nan:
    addsd   xmm0, xmm0
    ret

; -----------------------------------------------------------------------------
; gamf64__lgk - internal: lgamma(x) = (x - 1)(x - 2) K(x) for 0.5 <= x < 3
; args: xmm0 = x; returns xmm0. Clobbers xmm1-xmm3.
; -----------------------------------------------------------------------------
gamf64__lgk:
    movapd  xmm3, xmm0          ; x
    comisd  xmm0, [rel gamf64_one]
    jb      .k1
    comisd  xmm0, [rel gamf64_two]
    jb      .k2
    movapd  xmm1, xmm0
    subsd   xmm1, [rel gamf64_k3_c]
    mathfn_horner gamf64_k3, 21, xmm1, xmm2
    jmp     .scale
.k1:
    movapd  xmm1, xmm0
    subsd   xmm1, [rel gamf64_k1_c]
    mathfn_horner gamf64_k1, 23, xmm1, xmm2
    jmp     .scale
.k2:
    movapd  xmm1, xmm0
    subsd   xmm1, [rel gamf64_k2_c]
    mathfn_horner gamf64_k2, 23, xmm1, xmm2
.scale:
    movapd  xmm0, xmm3
    subsd   xmm0, [rel gamf64_one]  ; x - 1
    subsd   xmm3, [rel gamf64_two]  ; x - 2
    mulsd   xmm0, xmm3
    mulsd   xmm0, xmm2
    xorpd   xmm1, xmm1
    addsd   xmm0, xmm1          ; the exact zeros at 1 and 2 are +0, not -0
    ret

; -----------------------------------------------------------------------------
; gamf64__lgamma_pos - internal: lgamma(x) for finite x > 0
; args: xmm0 = x; returns xmm0
; -----------------------------------------------------------------------------
gamf64__lgamma_pos:
    sub     rsp, 40
    movsd   [rsp], xmm0         ; x
    comisd  xmm0, [rel gamf64_tiny]
    jb      .neg_log
    comisd  xmm0, [rel gamf64_half]
    jb      .below_half
    comisd  xmm0, [rel gamf64_three]
    jb      .fitted
    comisd  xmm0, [rel gamf64_four]
    jb      .shifted
    comisd  xmm0, [rel gamf64_171]
    jb      .direct
    ; Stirling
    call    umath_log_f64       ; ln x
    subsd   xmm0, [rel gamf64_one]
    movsd   xmm1, [rsp]
    subsd   xmm1, [rel gamf64_half]
    mulsd   xmm0, xmm1          ; (x - 1/2)(ln x - 1)
    movsd   [rsp + 8], xmm0
    movsd   xmm1, [rel gamf64_one]
    divsd   xmm1, [rsp]         ; z = 1/x
    movapd  xmm2, xmm1
    mulsd   xmm2, xmm1          ; z^2
    movsd   xmm3, [rel gamf64_s7]
    mulsd   xmm3, xmm2
    movsd   xmm4, [rel gamf64_s5]
    subsd   xmm4, xmm3
    mulsd   xmm4, xmm2
    movsd   xmm3, [rel gamf64_s3]
    subsd   xmm3, xmm4
    mulsd   xmm3, xmm2
    movsd   xmm4, [rel gamf64_s1]
    subsd   xmm4, xmm3
    mulsd   xmm4, xmm1          ; series
    addsd   xmm4, [rel gamf64_stirling_c]
    movsd   xmm0, [rsp + 8]
    addsd   xmm0, xmm4
    jmp     .out
.neg_log:
    call    umath_log_f64
    xorpd   xmm1, xmm1
    subsd   xmm1, xmm0
    movapd  xmm0, xmm1          ; -ln x
    jmp     .out
.below_half:
    call    gamf64__G           ; G(x)
    mulsd   xmm0, [rsp]
    call    umath_log1p_f64     ; ln Gamma(1 + x)
    movsd   [rsp + 8], xmm0
    movsd   xmm0, [rsp]
    call    umath_log_f64
    movsd   xmm1, [rsp + 8]
    subsd   xmm1, xmm0
    movapd  xmm0, xmm1
    jmp     .out
.fitted:
    call    gamf64__lgk
    jmp     .out
.shifted:
    subsd   xmm0, [rel gamf64_one]  ; x - 1, exact, in [3, 4) -> [2, 3)
    movsd   [rsp + 8], xmm0
    call    gamf64__lgk         ; lgamma(x - 1)
    movsd   [rsp + 16], xmm0
    movsd   xmm0, [rsp + 8]
    call    umath_log_f64       ; ln(x - 1)
    addsd   xmm0, [rsp + 16]
    jmp     .out
.direct:
    call    gamf64__scaled      ; M * 2^k
    mov     [rsp + 16], rax
    call    umath_log_f64       ; ln M
    cvtsi2sd xmm1, qword [rsp + 16]
    movapd  xmm2, xmm1
    mulsd   xmm1, [rel gamf64_ln2_lo]
    addsd   xmm0, xmm1
    mulsd   xmm2, [rel gamf64_ln2_hi]  ; exact
    addsd   xmm0, xmm2
.out:
    add     rsp, 40
    ret

; -----------------------------------------------------------------------------
; umath_lgamma_r_f64 - ln|Gamma(x)| and the sign of Gamma(x)
; args:    xmm0 = x, rdi = int32 *sign (may be NULL)
; returns: xmm0 = ln|Gamma(x)|; *sign = +1 or -1
; -----------------------------------------------------------------------------
global umath_lgamma_r_f64
umath_lgamma_r_f64:
    push    rbx
    sub     rsp, 32
    mov     rbx, rdi
    mov     dword [rsp + 24], 1 ; sign
    ucomisd xmm0, xmm0
    jp      .nan
    movq    rax, xmm0
    btr     rax, 63
    mov     rcx, 0x7FF0000000000000
    cmp     rax, rcx
    je      .pole               ; +-Inf -> +Inf
    xorpd   xmm1, xmm1
    ucomisd xmm0, xmm1
    je      .zero
    jb      .negative
    call    gamf64__lgamma_pos
    jmp     .store
.zero:
    movq    rax, xmm0
    test    rax, rax
    jns     .pole
    mov     dword [rsp + 24], -1
.pole:
    movsd   xmm0, [rel gamf64_inf]
    jmp     .store
.negative:
    call    gamf64__is_int
    je      .pole
    movsd   [rsp], xmm0         ; x
    movsd   xmm1, xmm0
    xorpd   xmm2, xmm2
    subsd   xmm2, xmm1
    comisd  xmm2, [rel gamf64_tiny]
    jae     .reflect
    movapd  xmm0, xmm2          ; tiny: Gamma(x) ~ 1/x < 0
    mov     dword [rsp + 24], -1
    call    umath_log_f64
    xorpd   xmm1, xmm1
    subsd   xmm1, xmm0
    movapd  xmm0, xmm1
    jmp     .store
.reflect:
    call    gamf64__sinpi
    movq    rax, xmm0
    test    rax, rax
    jns     .sign_ok
    mov     dword [rsp + 24], -1
.sign_ok:
    mulsd   xmm0, [rsp]         ; x sin(pi x)
    movq    rax, xmm0
    btr     rax, 63
    movq    xmm0, rax
    call    umath_log_f64       ; ln|x sin(pi x)|
    movsd   [rsp + 8], xmm0
    movsd   xmm0, [rsp]
    xorpd   xmm1, xmm1
    subsd   xmm1, xmm0
    movapd  xmm0, xmm1          ; -x
    call    gamf64__lgamma_pos
    movsd   xmm1, [rel gamf64_ln_pi]
    subsd   xmm1, [rsp + 8]
    subsd   xmm1, xmm0
    movapd  xmm0, xmm1
    jmp     .store
.nan:
    addsd   xmm0, xmm0
.store:
    test    rbx, rbx
    jz      .out
    mov     eax, [rsp + 24]
    mov     [rbx], eax
.out:
    add     rsp, 32
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; umath_lgamma_f64 - ln|Gamma(x)|
; args:    xmm0 = x
; returns: xmm0 = ln|Gamma(x)|
; -----------------------------------------------------------------------------
global umath_lgamma_f64
umath_lgamma_f64:
    xor     edi, edi
    jmp     umath_lgamma_r_f64

mathfn_unary_arrays umath_tgamma_f64, umath_tgamma_f64, 8
mathfn_unary_arrays umath_lgamma_f64, umath_lgamma_f64, 8

%endif ; GUARD_LIB_UMATH_MATH_FN_GAMMA_F64_ASM
