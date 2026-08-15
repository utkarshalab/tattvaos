%ifndef GUARD_LIB_UMATH_BITS_BIT32_ASM
%define GUARD_LIB_UMATH_BITS_BIT32_ASM
; =============================================================================
; umath - unified math library
; bits/bit32.asm - 32-bit operations (INT32/UINT32/FP32/TF32 bit manipulation)
; =============================================================================
; functions:
;   umath_bit32_rotl/rotr/bswap
;   umath_bit32_add_sat_s/add_sat_u/sub_sat_s/sub_sat_u
;   umath_bit32_max_s/min_s/max_u/min_u
;   umath_bit32_abs_s
;   umath_bit32_sign_extend64 / zero_extend64
;   umath_bit32_cmp_s/cmp_u
;   --- FP32 ---
;   umath_bit32_fp32_sign       (fp32 -> sign bit)
;   umath_bit32_fp32_exponent   (fp32 -> 8-bit exponent, raw)
;   umath_bit32_fp32_mantissa   (fp32 -> 23-bit mantissa)
;   umath_bit32_fp32_compose    (sign, exp, mant -> fp32 bits)
;   umath_bit32_fp32_is_nan
;   umath_bit32_fp32_is_inf
;   umath_bit32_fp32_is_zero
;   umath_bit32_fp32_is_denormal
;   umath_bit32_fp32_flip_sign
;   umath_bit32_fp32_abs
;   umath_bit32_fp32_negate
;   --- TF32 ---
;   umath_bit32_tf32_truncate   (fp32 -> tf32-rounded fp32, 10-bit mantissa)
;   umath_bit32_tf32_mantissa   (fp32 bits -> 10-bit tf32 mantissa, truncated)
; =============================================================================

bits 64
section .text

; =============================================================================
; generic 32-bit integer ops
; =============================================================================

global umath_bit32_rotl
umath_bit32_rotl:
    mov     eax, edi
    mov     cl, sil
    and     cl, 31
    rol     eax, cl
    ret

global umath_bit32_rotr
umath_bit32_rotr:
    mov     eax, edi
    mov     cl, sil
    and     cl, 31
    ror     eax, cl
    ret

global umath_bit32_bswap
umath_bit32_bswap:
    mov     eax, edi
    bswap   eax
    ret

; -----------------------------------------------------------------------------
; umath_bit32_add_sat_s - saturating signed INT32 add
; args: edi=a, esi=b (i32)   returns: eax = result
; uses 64-bit intermediate to avoid overflow on the add itself
; -----------------------------------------------------------------------------
global umath_bit32_add_sat_s
umath_bit32_add_sat_s:
    movsxd  rax, edi
    movsxd  rcx, esi
    add     rax, rcx
    cmp     rax, 0x7FFFFFFF
    jg      .max
    cmp     rax, -2147483648
    jl      .min
    jmp     .pack
.max: mov rax, 0x7FFFFFFF
      jmp .pack
.min: mov rax, -2147483648
.pack:
    mov     eax, eax        ; truncate to 32 bits (zero upper via mov)
    ret

global umath_bit32_add_sat_u
umath_bit32_add_sat_u:
    mov     eax, edi
    mov     ecx, esi
    add     rax, rcx        ; rax = zero-extended edi + zero-extended esi (no overflow, max 2^33)
    mov     rcx, rax
    movzx   rax, eax
    cmp     rax, 0xFFFFFFFF
    jbe     .done
    mov     eax, 0xFFFFFFFF
    ret
.done:
    ; rax currently holds zero-extended sum already <= 0xFFFFFFFF
    ret

global umath_bit32_sub_sat_s
umath_bit32_sub_sat_s:
    movsxd  rax, edi
    movsxd  rcx, esi
    sub     rax, rcx
    cmp     rax, 0x7FFFFFFF
    jg      .max
    cmp     rax, -2147483648
    jl      .min
    jmp     .pack
.max: mov rax, 0x7FFFFFFF
      jmp .pack
.min: mov rax, -2147483648
.pack:
    mov     eax, eax
    ret

global umath_bit32_sub_sat_u
umath_bit32_sub_sat_u:
    mov     eax, edi
    mov     ecx, esi
    cmp     eax, ecx
    jae     .sub
    xor     eax, eax
    ret
.sub:
    sub     eax, ecx
    ret

global umath_bit32_max_s
umath_bit32_max_s:
    mov     eax, edi
    cmp     eax, esi
    jge     .done
    mov     eax, esi
.done:
    ret

global umath_bit32_min_s
umath_bit32_min_s:
    mov     eax, edi
    cmp     eax, esi
    jle     .done
    mov     eax, esi
.done:
    ret

global umath_bit32_max_u
umath_bit32_max_u:
    mov     eax, edi
    cmp     eax, esi
    jae     .done
    mov     eax, esi
.done:
    ret

global umath_bit32_min_u
umath_bit32_min_u:
    mov     eax, edi
    cmp     eax, esi
    jbe     .done
    mov     eax, esi
.done:
    ret

; -----------------------------------------------------------------------------
; umath_bit32_abs_s - absolute value, saturate INT32_MIN -> INT32_MAX
; -----------------------------------------------------------------------------
global umath_bit32_abs_s
umath_bit32_abs_s:
    mov     eax, edi
    test    eax, eax
    jge     .done
    ; check for INT32_MIN
    cmp     eax, 0x80000000
    jne     .neg
    mov     eax, 0x7FFFFFFF
    ret
.neg:
    neg     eax
.done:
    ret

global umath_bit32_sign_extend64
umath_bit32_sign_extend64:
    movsxd  rax, edi
    ret

global umath_bit32_zero_extend64
umath_bit32_zero_extend64:
    mov     eax, edi
    ret

global umath_bit32_cmp_s
umath_bit32_cmp_s:
    mov     eax, edi
    cmp     eax, esi
    je      .eq
    jl      .lt
    mov     eax, 1
    ret
.eq: xor eax, eax
     ret
.lt: mov eax, -1
     ret

global umath_bit32_cmp_u
umath_bit32_cmp_u:
    mov     eax, edi
    cmp     eax, esi
    je      .eq
    jb      .lt
    mov     eax, 1
    ret
.eq: xor eax, eax
     ret
.lt: mov eax, -1
     ret

; =============================================================================
; FP32 bit field operations
; layout: [31]=sign [30:23]=exponent(8) [22:0]=mantissa(23)
; =============================================================================

global umath_bit32_fp32_sign
umath_bit32_fp32_sign:
    mov     eax, edi
    shr     eax, 31
    ret

global umath_bit32_fp32_exponent
umath_bit32_fp32_exponent:
    mov     eax, edi
    shr     eax, 23
    and     eax, 0xFF
    ret

global umath_bit32_fp32_mantissa
umath_bit32_fp32_mantissa:
    mov     eax, edi
    and     eax, 0x7FFFFF
    ret

; -----------------------------------------------------------------------------
; umath_bit32_fp32_compose - build fp32 bits from sign/exp/mantissa
; args: edi=sign(0/1), esi=exponent(0-255), edx=mantissa(0-0x7FFFFF)
; returns: eax = fp32 bits
; -----------------------------------------------------------------------------
global umath_bit32_fp32_compose
umath_bit32_fp32_compose:
    mov     eax, edi
    and     eax, 1
    shl     eax, 31
    mov     ecx, esi
    and     ecx, 0xFF
    shl     ecx, 23
    or      eax, ecx
    mov     ecx, edx
    and     ecx, 0x7FFFFF
    or      eax, ecx
    ret

; -----------------------------------------------------------------------------
; umath_bit32_fp32_is_nan - check NaN (exp=255, mantissa!=0)
; -----------------------------------------------------------------------------
global umath_bit32_fp32_is_nan
umath_bit32_fp32_is_nan:
    mov     eax, edi
    and     eax, 0x7FFFFFFF
    cmp     eax, 0x7F800000
    jbe     .no
    mov     eax, 1
    ret
.no:
    xor     eax, eax
    ret

global umath_bit32_fp32_is_inf
umath_bit32_fp32_is_inf:
    mov     eax, edi
    and     eax, 0x7FFFFFFF
    cmp     eax, 0x7F800000
    sete    al
    movzx   eax, al
    ret

global umath_bit32_fp32_is_zero
umath_bit32_fp32_is_zero:
    mov     eax, edi
    and     eax, 0x7FFFFFFF
    test    eax, eax
    setz    al
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_bit32_fp32_is_denormal - exp=0 and mantissa!=0
; -----------------------------------------------------------------------------
global umath_bit32_fp32_is_denormal
umath_bit32_fp32_is_denormal:
    mov     eax, edi
    and     eax, 0x7FFFFFFF
    test    eax, eax
    jz      .no
    cmp     eax, 0x007FFFFF
    ja      .no
    mov     eax, 1
    ret
.no:
    xor     eax, eax
    ret

global umath_bit32_fp32_flip_sign
umath_bit32_fp32_flip_sign:
    mov     eax, edi
    xor     eax, 0x80000000
    ret

global umath_bit32_fp32_abs
umath_bit32_fp32_abs:
    mov     eax, edi
    and     eax, 0x7FFFFFFF
    ret

global umath_bit32_fp32_negate
umath_bit32_fp32_negate:
    mov     eax, edi
    xor     eax, 0x80000000
    ret

; =============================================================================
; TF32 operations
; TF32 = FP32 storage with 10-bit mantissa (rounds off lower 13 mantissa bits)
; layout matches FP32: [31]=sign [30:23]=exp(8) [22:13]=mantissa(10) [12:0]=truncated
; =============================================================================

; -----------------------------------------------------------------------------
; umath_bit32_tf32_truncate - round fp32 bits to TF32 precision (10-bit mantissa)
; args: edi = fp32 bits
; returns: eax = fp32 bits with lower 13 mantissa bits cleared (round-to-zero)
; note:    this is truncation, not round-to-nearest; caller may add
;          rounding bias before calling for round-to-nearest behavior
; -----------------------------------------------------------------------------
global umath_bit32_tf32_truncate
umath_bit32_tf32_truncate:
    mov     eax, edi
    and     eax, 0xFFFFE000         ; clear lowest 13 mantissa bits
    ret

; -----------------------------------------------------------------------------
; umath_bit32_tf32_mantissa - extract 10-bit TF32 mantissa from fp32 bits
; args: edi = fp32 bits
; returns: eax = top 10 bits of the 23-bit mantissa (0-1023)
; -----------------------------------------------------------------------------
global umath_bit32_tf32_mantissa
umath_bit32_tf32_mantissa:
    mov     eax, edi
    and     eax, 0x7FFFFF
    shr     eax, 13                 ; keep top 10 of 23 bits
    ret
%endif ; GUARD_LIB_UMATH_BITS_BIT32_ASM
