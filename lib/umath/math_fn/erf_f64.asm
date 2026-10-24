%ifndef GUARD_LIB_UMATH_MATH_FN_ERF_F64_ASM
%define GUARD_LIB_UMATH_MATH_FN_ERF_F64_ASM
; =============================================================================
; umath - unified math library
; math_fn/erf_f64.asm - error function and complementary error function
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; With a = |x| (erf is odd; erfc(-x) = 2 - erfc(x)):
;
;   a < 1       erf(a) = a * E(a^2), E(t) = erf(sqrt t)/sqrt t, degree 11
;   a >= 0.5    erfc(a) = e^(-a^2) * erfcx(a), erfcx(a) = erfc(a)*e^(a^2):
;                 a < 2:   erfcx = P(a - 1.25),                 degree 19
;                 a < 6:   erfcx = H(u)/a, u = 1/a^2 in [1/36, 1/4], degree 21
;                 a < 27.4: erfcx = H(u)/a, u in [1/750, 1/36],  degree 11
;               H(u) = a*erfcx(a) is smooth in u. e^(-a^2) uses the exact
;               split a^2 = hi + lo (Dekker's product, no FMA needed):
;               e^(-a^2) = e^(-hi) * (1 - lo), so the rounding of a^2 --
;               which e^() would magnify by up to 750 -- never enters.
;   erf(a)  = 1 - erfc(a) for 1 <= a < 6 (erfc <= 0.16: no cancellation),
;             1 from 6 on (erfc(6) = 2e-17, below half an ULP of 1);
;   erfc(a) = 1 - erf(a) for a < 0.5 (erf <= 0.53), 0 from 27.4 on.
;
; The kernels are Chebyshev fits made for this file (mpmath, 60 digits),
; each in a variable centred on its interval; evaluated in double they are
; within 1.3-1.9e-16 relative of the true function.
;
; erf: +-0 -> +-0, +-Inf -> +-1. erfc: +Inf -> +0, -Inf -> 2. NaN
; propagates (quieted).
; =============================================================================

bits 64

%include "lib/umath/math_fn/exp_f64.asm"
%include "lib/umath/math_fn/polyval.asm"
%include "lib/umath/math_fn/loops.asm"

section .rodata
align 8
erff64_one:         dq 1.0
erff64_two:         dq 2.0
erff64_half:        dq 0.5
erff64_six:         dq 6.0
erff64_cut_erfc:    dq 27.4
erff64_split:       dq 134217729.0
erff64_c_a:         dq 1.25
erff64_c_b:         dq 0x3FC1C71C71C71C72       ; 0.1388888888888889
erff64_c_c:         dq 0x3F8DB22D0E560419       ; 0.0145
erff64_k_erf:       ; E(t), 12 coefficients, highest degree first
    dq 0xBE0AC9585A44FE29, 0x3E4D76AF6CA49787, 0xBE85C131500D3F88
    dq 0x3EBB981D78881A5D, 0xBEEF4CA838ADB73B, 0x3F1F9A2BE4F731A1
    dq 0xBF4C02DB0665E53D, 0x3F7565BCCFA44156, 0xBF9B82CE31203772
    dq 0x3FBCE2F21A040F66, 0xBFD812746B0379C1, 0x3FF20DD750429B6D
erff64_k_a:         ; erfcx(a), s = a - 1.25, 20 coefficients
    dq 0xBE0E6880B3E6E59F, 0x3E2D3BEABE60AD52, 0xBE463200E045B8C4
    dq 0x3E6442FC009CA791, 0xBE827857C651AA40, 0x3EA01C0E7CD302B4
    dq 0xBEBB5B8F579866B9, 0x3ED6A15568A5632F, 0xBEF22FC4E1DAC054
    dq 0x3F0C57050ABF75F8, 0xBF255C07CE113526, 0x3F3F0FE6F32F5CD4
    dq 0xBF55B8BC94D17F85, 0x3F6D1B695AC27C52, 0xBF8299636D6C488C
    dq 0x3F968A25A663FF1E, 0xBFA9B635AC624AE6, 0x3FBB56F45EEF7E7B
    dq 0xBFCABAACDBFA8B07, 0x3FD78A692138767A
erff64_k_b:         ; H(u), s = u - 0.13888.., 22 coefficients
    dq 0xC1BF3648969032D0, 0x419EA4339EF5804B, 0x414B4377BC6AD315
    dq 0xC123C16C6757D438, 0xC12CD7EEFFB08ED2, 0x410E6F219B7A6F1E
    dq 0xC0E864C1E362A618, 0x40CC006C6DEA4AF6, 0xC0B12B938CC1E5FC
    dq 0x40949DF30ED21856, 0xC0797EB4BE18127C, 0x406068D935EAE930
    dq 0xC04607746517D725, 0x402F0B32C434C40B, 0xC0172B82FE8A6E67
    dq 0x400289DF79DF58A3, 0xBFF02B677F61AED9, 0x3FDF84D90AB32FA9
    dq 0xBFD1DABC9A1CDB7A, 0x3FC93B99990776E6, 0xBFC9F5383D721DFD
    dq 0x3FE0FFAFF540DFE0
erff64_k_c:         ; H(u), s = u - 0.0145, 12 coefficients
    dq 0xC125630E4780F592, 0x40F543718F8DB9EF, 0xC0C60F02603E33A7
    dq 0x409A01613581E420, 0xC07104221E9C783A, 0x4049217B451204C8
    dq 0xC02571A35A43F8CF, 0x4005D9C0C7E460CA, 0xBFEBF26629C8F809
    dq 0x3FD867E833E975F3, 0xBFD14F09D90BEEA4, 0x3FE1ED094F645D4F

section .text

; -----------------------------------------------------------------------------
; erff64__small - internal: erf(a) for 0 <= a < 1
; args: xmm0 = a; returns xmm0 = erf(a). Clobbers xmm1, xmm2.
; -----------------------------------------------------------------------------
erff64__small:
    movapd  xmm1, xmm0
    mulsd   xmm1, xmm0          ; t = a^2
    mathfn_horner erff64_k_erf, 12, xmm1, xmm2
    mulsd   xmm0, xmm2
    ret

; -----------------------------------------------------------------------------
; erff64__tail - internal: erfc(a) for 0.5 <= a < 27.4
; args: xmm0 = a; returns xmm0 = erfc(a)
; Clobbers what umath_exp_f64 clobbers, plus xmm3, xmm5-xmm7.
; -----------------------------------------------------------------------------
erff64__tail:
    sub     rsp, 40
    movsd   [rsp], xmm0         ; a
    ; a^2 = hi + lo exactly
    movapd  xmm1, xmm0
    mulsd   xmm1, xmm0          ; hi
    movsd   xmm2, [rel erff64_split]
    mulsd   xmm2, xmm0
    movapd  xmm3, xmm2
    subsd   xmm3, xmm0
    subsd   xmm2, xmm3          ; ah
    movapd  xmm3, xmm0
    subsd   xmm3, xmm2          ; al
    movapd  xmm5, xmm2
    mulsd   xmm5, xmm2
    subsd   xmm5, xmm1          ; ah*ah - hi
    movapd  xmm6, xmm2
    mulsd   xmm6, xmm3
    addsd   xmm5, xmm6
    addsd   xmm5, xmm6          ; + 2*ah*al
    movapd  xmm6, xmm3
    mulsd   xmm6, xmm3
    addsd   xmm5, xmm6          ; lo
    movsd   [rsp + 8], xmm1     ; hi
    movsd   [rsp + 16], xmm5    ; lo
    ; erfcx(a)
    comisd  xmm0, [rel erff64_two]
    jae     .far
    movapd  xmm1, xmm0
    subsd   xmm1, [rel erff64_c_a]
    mathfn_horner erff64_k_a, 20, xmm1, xmm2
    jmp     .have_k
.far:
    movsd   xmm1, [rel erff64_one]
    divsd   xmm1, [rsp + 8]     ; u = 1/a^2
    comisd  xmm0, [rel erff64_six]
    jae     .farthest
    subsd   xmm1, [rel erff64_c_b]
    mathfn_horner erff64_k_b, 22, xmm1, xmm2
    jmp     .over_a
.farthest:
    subsd   xmm1, [rel erff64_c_c]
    mathfn_horner erff64_k_c, 12, xmm1, xmm2
.over_a:
    divsd   xmm2, [rsp]         ; H(u)/a
.have_k:
    movsd   [rsp + 24], xmm2
    movsd   xmm0, [rsp + 8]
    xorpd   xmm1, xmm1
    subsd   xmm1, xmm0
    movapd  xmm0, xmm1          ; -hi
    call    umath_exp_f64
    movsd   xmm1, [rel erff64_one]
    subsd   xmm1, [rsp + 16]    ; 1 - lo
    mulsd   xmm0, xmm1
    mulsd   xmm0, [rsp + 24]
    add     rsp, 40
    ret

; -----------------------------------------------------------------------------
; umath_erf_f64 - error function
; args:    xmm0 = x
; returns: xmm0 = erf(x), in [-1, 1]
; -----------------------------------------------------------------------------
global umath_erf_f64
umath_erf_f64:
    ucomisd xmm0, xmm0
    jp      .nan
    movq    rax, xmm0
    mov     rdx, rax
    btr     rax, 63
    xor     rdx, rax            ; sign bit
    movq    xmm0, rax           ; a
    comisd  xmm0, [rel erff64_one]
    jae     .large
    call    erff64__small
    jmp     .sign
.large:
    comisd  xmm0, [rel erff64_six]
    jae     .one
    sub     rsp, 24
    mov     [rsp], rdx
    call    erff64__tail
    movsd   xmm1, [rel erff64_one]
    subsd   xmm1, xmm0
    movapd  xmm0, xmm1          ; 1 - erfc(a)
    mov     rdx, [rsp]
    add     rsp, 24
    jmp     .sign
.one:
    movsd   xmm0, [rel erff64_one]
.sign:
    movq    rax, xmm0
    or      rax, rdx
    movq    xmm0, rax
    ret
.nan:
    addsd   xmm0, xmm0
    ret

; -----------------------------------------------------------------------------
; umath_erfc_f64 - complementary error function
; args:    xmm0 = x
; returns: xmm0 = erfc(x) = 1 - erf(x), in [0, 2]
; -----------------------------------------------------------------------------
global umath_erfc_f64
umath_erfc_f64:
    ucomisd xmm0, xmm0
    jp      .nan
    sub     rsp, 24
    movq    rax, xmm0
    mov     rdx, rax
    btr     rax, 63
    xor     rdx, rax            ; sign bit
    mov     [rsp], rdx
    movq    xmm0, rax           ; a
    comisd  xmm0, [rel erff64_half]
    jb      .near_zero
    comisd  xmm0, [rel erff64_cut_erfc]
    jae     .tiny_tail
    call    erff64__tail        ; erfc(a)
    jmp     .reflect
.tiny_tail:
    xorpd   xmm0, xmm0          ; erfc(a) underflows to 0
.reflect:
    mov     rdx, [rsp]
    test    rdx, rdx
    jz      .done
    movsd   xmm1, [rel erff64_two]
    subsd   xmm1, xmm0          ; erfc(-a) = 2 - erfc(a)
    movapd  xmm0, xmm1
    jmp     .done
.near_zero:
    call    erff64__small       ; erf(a), a < 0.5
    mov     rdx, [rsp]
    movq    rax, xmm0
    or      rax, rdx
    movq    xmm0, rax           ; erf(x)
    movsd   xmm1, [rel erff64_one]
    subsd   xmm1, xmm0
    movapd  xmm0, xmm1          ; 1 - erf(x)
.done:
    add     rsp, 24
    ret
.nan:
    addsd   xmm0, xmm0
    ret

mathfn_unary_arrays umath_erf_f64, umath_erf_f64, 8
mathfn_unary_arrays umath_erfc_f64, umath_erfc_f64, 8

%endif ; GUARD_LIB_UMATH_MATH_FN_ERF_F64_ASM
