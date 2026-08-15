%ifndef GUARD_LIB_UMATH_BITS_BIT64_ASM
%define GUARD_LIB_UMATH_BITS_BIT64_ASM
; =============================================================================
; umath - unified math library
; bits/bit64.asm - 64-bit operations (INT64/UINT64/FP64 bit manipulation)
; =============================================================================
; functions:
;   umath_bit64_rotl/rotr/bswap
;   umath_bit64_add_sat_s/add_sat_u/sub_sat_s/sub_sat_u
;   umath_bit64_max_s/min_s/max_u/min_u
;   umath_bit64_abs_s
;   umath_bit64_cmp_s/cmp_u
;   --- FP64 ---
;   umath_bit64_fp64_sign       (fp64 -> sign bit)
;   umath_bit64_fp64_exponent   (fp64 -> 11-bit exponent, raw)
;   umath_bit64_fp64_mantissa   (fp64 -> 52-bit mantissa)
;   umath_bit64_fp64_compose    (sign, exp, mant -> fp64 bits)
;   umath_bit64_fp64_is_nan
;   umath_bit64_fp64_is_inf
;   umath_bit64_fp64_is_zero
;   umath_bit64_fp64_is_denormal
;   umath_bit64_fp64_flip_sign
;   umath_bit64_fp64_abs
;   umath_bit64_fp64_negate
;   --- CF32 (complex FP32: packed as [im:f32 | re:f32] in one u64) ---
;   umath_bit64_cf32_real       (cf32 bits -> real part fp32 bits, zero-ext)
;   umath_bit64_cf32_imag       (cf32 bits -> imag part fp32 bits, zero-ext)
;   umath_bit64_cf32_compose    (re_bits, im_bits -> cf32 packed u64)
;   umath_bit64_cf32_conjugate  (cf32 bits -> cf32 with imag sign flipped)
; =============================================================================

bits 64
section .text

; =============================================================================
; generic 64-bit integer ops
; =============================================================================

global umath_bit64_rotl
umath_bit64_rotl:
    mov     rax, rdi
    mov     cl, sil
    and     cl, 63
    rol     rax, cl
    ret

global umath_bit64_rotr
umath_bit64_rotr:
    mov     rax, rdi
    mov     cl, sil
    and     cl, 63
    ror     rax, cl
    ret

global umath_bit64_bswap
umath_bit64_bswap:
    mov     rax, rdi
    bswap   rax
    ret

; -----------------------------------------------------------------------------
; umath_bit64_add_sat_s - saturating signed INT64 add
; args: rdi=a, rsi=b (i64)   returns: rax = result
; uses overflow flag from signed add to detect saturation
; -----------------------------------------------------------------------------
global umath_bit64_add_sat_s
umath_bit64_add_sat_s:
    mov     rax, rdi
    add     rax, rsi
    jno     .done                   ; no overflow -> done
    ; overflow occurred: result saturates based on sign of operands
    ; if both operands positive -> overflow to +inf (INT64_MAX)
    ; if both operands negative -> overflow to -inf (INT64_MIN)
    test    rdi, rdi
    js      .neg_sat
    mov     rax, 0x7FFFFFFFFFFFFFFF
    ret
.neg_sat:
    mov     rax, 0x8000000000000000
.done:
    ret

; -----------------------------------------------------------------------------
; umath_bit64_add_sat_u - saturating unsigned UINT64 add
; args: rdi=a, rsi=b (u64)   returns: rax = result
; uses carry flag to detect overflow
; -----------------------------------------------------------------------------
global umath_bit64_add_sat_u
umath_bit64_add_sat_u:
    mov     rax, rdi
    add     rax, rsi
    jnc     .done
    mov     rax, 0xFFFFFFFFFFFFFFFF
.done:
    ret

; -----------------------------------------------------------------------------
; umath_bit64_sub_sat_s - saturating signed INT64 sub
; -----------------------------------------------------------------------------
global umath_bit64_sub_sat_s
umath_bit64_sub_sat_s:
    mov     rax, rdi
    sub     rax, rsi
    jno     .done
    ; overflow: if a >= 0 and b < 0 -> result overflowed positive -> sat max
    ;           if a < 0 and b >= 0 -> result overflowed negative -> sat min
    test    rdi, rdi
    js      .a_neg
    mov     rax, 0x7FFFFFFFFFFFFFFF
    ret
.a_neg:
    mov     rax, 0x8000000000000000
.done:
    ret

; -----------------------------------------------------------------------------
; umath_bit64_sub_sat_u - saturating unsigned UINT64 sub, clamp to 0
; -----------------------------------------------------------------------------
global umath_bit64_sub_sat_u
umath_bit64_sub_sat_u:
    mov     rax, rdi
    cmp     rax, rsi
    jae     .sub
    xor     eax, eax
    ret
.sub:
    sub     rax, rsi
    ret

global umath_bit64_max_s
umath_bit64_max_s:
    mov     rax, rdi
    cmp     rax, rsi
    jge     .done
    mov     rax, rsi
.done:
    ret

global umath_bit64_min_s
umath_bit64_min_s:
    mov     rax, rdi
    cmp     rax, rsi
    jle     .done
    mov     rax, rsi
.done:
    ret

global umath_bit64_max_u
umath_bit64_max_u:
    mov     rax, rdi
    cmp     rax, rsi
    jae     .done
    mov     rax, rsi
.done:
    ret

global umath_bit64_min_u
umath_bit64_min_u:
    mov     rax, rdi
    cmp     rax, rsi
    jbe     .done
    mov     rax, rsi
.done:
    ret

; -----------------------------------------------------------------------------
; umath_bit64_abs_s - absolute value, saturate INT64_MIN -> INT64_MAX
; -----------------------------------------------------------------------------
global umath_bit64_abs_s
umath_bit64_abs_s:
    mov     rax, rdi
    test    rax, rax
    jge     .done
    cmp     rax, 0x8000000000000000
    jne     .neg
    mov     rax, 0x7FFFFFFFFFFFFFFF
    ret
.neg:
    neg     rax
.done:
    ret

global umath_bit64_cmp_s
umath_bit64_cmp_s:
    mov     rax, rdi
    cmp     rax, rsi
    je      .eq
    jl      .lt
    mov     eax, 1
    ret
.eq: xor eax, eax
     ret
.lt: mov eax, -1
     ret

global umath_bit64_cmp_u
umath_bit64_cmp_u:
    mov     rax, rdi
    cmp     rax, rsi
    je      .eq
    jb      .lt
    mov     eax, 1
    ret
.eq: xor eax, eax
     ret
.lt: mov eax, -1
     ret

; =============================================================================
; FP64 bit field operations
; layout: [63]=sign [62:52]=exponent(11) [51:0]=mantissa(52)
; =============================================================================

global umath_bit64_fp64_sign
umath_bit64_fp64_sign:
    mov     rax, rdi
    shr     rax, 63
    ret

global umath_bit64_fp64_exponent
umath_bit64_fp64_exponent:
    mov     rax, rdi
    shr     rax, 52
    and     rax, 0x7FF
    ret

global umath_bit64_fp64_mantissa
umath_bit64_fp64_mantissa:
    mov     rax, rdi
    mov     rcx, 0x000FFFFFFFFFFFFF
    and     rax, rcx
    ret

; -----------------------------------------------------------------------------
; umath_bit64_fp64_compose - build fp64 bits from sign/exp/mantissa
; args: rdi=sign(0/1), rsi=exponent(0-2047), rdx=mantissa(0-2^52-1)
; returns: rax = fp64 bits
; -----------------------------------------------------------------------------
global umath_bit64_fp64_compose
umath_bit64_fp64_compose:
    mov     rax, rdi
    and     rax, 1
    shl     rax, 63
    mov     rcx, rsi
    and     rcx, 0x7FF
    shl     rcx, 52
    or      rax, rcx
    mov     rcx, rdx
    mov     r8, 0x000FFFFFFFFFFFFF
    and     rcx, r8
    or      rax, rcx
    ret

; -----------------------------------------------------------------------------
; umath_bit64_fp64_is_nan - exp=2047, mantissa!=0
; -----------------------------------------------------------------------------
global umath_bit64_fp64_is_nan
umath_bit64_fp64_is_nan:
    mov     rax, rdi
    mov     rcx, 0x7FFFFFFFFFFFFFFF
    and     rax, rcx
    mov     rcx, 0x7FF0000000000000
    cmp     rax, rcx
    jbe     .no
    mov     eax, 1
    ret
.no:
    xor     eax, eax
    ret

global umath_bit64_fp64_is_inf
umath_bit64_fp64_is_inf:
    mov     rax, rdi
    mov     rcx, 0x7FFFFFFFFFFFFFFF
    and     rax, rcx
    mov     rcx, 0x7FF0000000000000
    cmp     rax, rcx
    sete    al
    movzx   eax, al
    ret

global umath_bit64_fp64_is_zero
umath_bit64_fp64_is_zero:
    mov     rax, rdi
    mov     rcx, 0x7FFFFFFFFFFFFFFF
    and     rax, rcx
    test    rax, rax
    setz    al
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_bit64_fp64_is_denormal - exp=0, mantissa!=0
; -----------------------------------------------------------------------------
global umath_bit64_fp64_is_denormal
umath_bit64_fp64_is_denormal:
    mov     rax, rdi
    mov     rcx, 0x7FFFFFFFFFFFFFFF
    and     rax, rcx
    test    rax, rax
    jz      .no
    mov     rcx, 0x000FFFFFFFFFFFFF
    cmp     rax, rcx
    ja      .no
    mov     eax, 1
    ret
.no:
    xor     eax, eax
    ret

global umath_bit64_fp64_flip_sign
umath_bit64_fp64_flip_sign:
    mov     rax, rdi
    mov     rcx, 0x8000000000000000
    xor     rax, rcx
    ret

global umath_bit64_fp64_abs
umath_bit64_fp64_abs:
    mov     rax, rdi
    mov     rcx, 0x7FFFFFFFFFFFFFFF
    and     rax, rcx
    ret

global umath_bit64_fp64_negate
umath_bit64_fp64_negate:
    mov     rax, rdi
    mov     rcx, 0x8000000000000000
    xor     rax, rcx
    ret

; =============================================================================
; CF32 operations - complex FP32 packed as single u64
; layout convention: low 32 bits = real part, high 32 bits = imaginary part
; =============================================================================

; -----------------------------------------------------------------------------
; umath_bit64_cf32_real - extract real part (fp32 bits, zero-extended)
; args: rdi = cf32 packed bits
; returns: eax = real part fp32 bits
; -----------------------------------------------------------------------------
global umath_bit64_cf32_real
umath_bit64_cf32_real:
    mov     eax, edi            ; low 32 bits
    ret

; -----------------------------------------------------------------------------
; umath_bit64_cf32_imag - extract imaginary part (fp32 bits, zero-extended)
; args: rdi = cf32 packed bits
; returns: eax = imaginary part fp32 bits
; -----------------------------------------------------------------------------
global umath_bit64_cf32_imag
umath_bit64_cf32_imag:
    mov     rax, rdi
    shr     rax, 32
    ret

; -----------------------------------------------------------------------------
; umath_bit64_cf32_compose - pack real and imaginary fp32 bits into cf32 u64
; args: edi = real part (fp32 bits), esi = imaginary part (fp32 bits)
; returns: rax = packed cf32 (im in high 32, re in low 32)
; -----------------------------------------------------------------------------
global umath_bit64_cf32_compose
umath_bit64_cf32_compose:
    mov     eax, edi            ; re in low 32
    mov     rcx, rsi
    shl     rcx, 32             ; im in high 32
    or      rax, rcx
    ret

; -----------------------------------------------------------------------------
; umath_bit64_cf32_conjugate - flip sign of imaginary part
; args: rdi = cf32 packed bits
; returns: rax = packed cf32 with imaginary sign flipped
; -----------------------------------------------------------------------------
global umath_bit64_cf32_conjugate
umath_bit64_cf32_conjugate:
    mov     rax, rdi
    mov     rcx, 0x8000000000000000   ; sign bit of imag part (bit 63)
    xor     rax, rcx
    ret
%endif ; GUARD_LIB_UMATH_BITS_BIT64_ASM
