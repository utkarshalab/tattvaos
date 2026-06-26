; =============================================================================
; umath - unified math library
; bits/bit16.asm - 16-bit operations (INT16/UINT16/FP16/BF16 bit manipulation)
; =============================================================================
; functions:
;   umath_bit16_rotl         (val, amount -> rotated word)
;   umath_bit16_rotr         (val, amount -> rotated word)
;   umath_bit16_bswap        (val -> byte-swapped word)
;   umath_bit16_add_sat_s    (a, b -> saturating signed INT16 add)
;   umath_bit16_add_sat_u    (a, b -> saturating unsigned UINT16 add)
;   umath_bit16_sub_sat_s    (a, b -> saturating signed INT16 sub)
;   umath_bit16_sub_sat_u    (a, b -> saturating unsigned UINT16 sub)
;   umath_bit16_max_s/min_s/max_u/min_u
;   umath_bit16_abs_s        (a -> |a|, saturate -32768 -> 32767)
;   umath_bit16_sign_extend32/64
;   umath_bit16_zero_extend32/64
;   umath_bit16_cmp_s/cmp_u
;   --- FP16 ---
;   umath_bit16_fp16_sign       (fp16 -> sign bit)
;   umath_bit16_fp16_exponent   (fp16 -> 5-bit exponent, raw)
;   umath_bit16_fp16_mantissa   (fp16 -> 10-bit mantissa)
;   umath_bit16_fp16_compose    (sign, exp, mant -> fp16 bits)
;   umath_bit16_fp16_is_nan
;   umath_bit16_fp16_is_inf
;   umath_bit16_fp16_is_zero
;   umath_bit16_fp16_flip_sign
;   umath_bit16_fp16_abs
;   --- BF16 ---
;   umath_bit16_bf16_sign       (bf16 -> sign bit)
;   umath_bit16_bf16_exponent   (bf16 -> 8-bit exponent, raw)
;   umath_bit16_bf16_mantissa   (bf16 -> 7-bit mantissa)
;   umath_bit16_bf16_compose    (sign, exp, mant -> bf16 bits)
;   umath_bit16_bf16_is_nan
;   umath_bit16_bf16_is_inf
;   umath_bit16_bf16_is_zero
;   umath_bit16_bf16_flip_sign
;   umath_bit16_bf16_abs
; =============================================================================

bits 64
section .text

; =============================================================================
; generic 16-bit integer ops
; =============================================================================

global umath_bit16_rotl
umath_bit16_rotl:
    mov     ax, di
    mov     cl, sil
    and     cl, 15
    rol     ax, cl
    movzx   eax, ax
    ret

global umath_bit16_rotr
umath_bit16_rotr:
    mov     ax, di
    mov     cl, sil
    and     cl, 15
    ror     ax, cl
    movzx   eax, ax
    ret

global umath_bit16_bswap
umath_bit16_bswap:
    mov     ax, di
    rol     ax, 8
    movzx   eax, ax
    ret

; -----------------------------------------------------------------------------
; umath_bit16_add_sat_s - saturating signed INT16 add [-32768,32767]
; args: di=a, si=b (i16)   returns: ax = result
; -----------------------------------------------------------------------------
global umath_bit16_add_sat_s
umath_bit16_add_sat_s:
    movsx   eax, di
    movsx   ecx, si
    add     eax, ecx
    cmp     eax, 32767
    jg      .max
    cmp     eax, -32768
    jl      .min
    jmp     .pack
.max: mov eax, 32767
      jmp .pack
.min: mov eax, -32768
.pack:
    movzx   eax, ax
    ret

global umath_bit16_add_sat_u
umath_bit16_add_sat_u:
    movzx   eax, di
    movzx   ecx, si
    add     eax, ecx
    cmp     eax, 0xFFFF
    jbe     .done
    mov     eax, 0xFFFF
.done:
    movzx   eax, ax
    ret

global umath_bit16_sub_sat_s
umath_bit16_sub_sat_s:
    movsx   eax, di
    movsx   ecx, si
    sub     eax, ecx
    cmp     eax, 32767
    jg      .max
    cmp     eax, -32768
    jl      .min
    jmp     .pack
.max: mov eax, 32767
      jmp .pack
.min: mov eax, -32768
.pack:
    movzx   eax, ax
    ret

global umath_bit16_sub_sat_u
umath_bit16_sub_sat_u:
    movzx   eax, di
    movzx   ecx, si
    cmp     eax, ecx
    jae     .sub
    xor     eax, eax
    ret
.sub:
    sub     eax, ecx
    movzx   eax, ax
    ret

global umath_bit16_max_s
umath_bit16_max_s:
    movsx   eax, di
    movsx   ecx, si
    cmp     eax, ecx
    jge     .done
    mov     eax, ecx
.done:
    movzx   eax, ax
    ret

global umath_bit16_min_s
umath_bit16_min_s:
    movsx   eax, di
    movsx   ecx, si
    cmp     eax, ecx
    jle     .done
    mov     eax, ecx
.done:
    movzx   eax, ax
    ret

global umath_bit16_max_u
umath_bit16_max_u:
    movzx   eax, di
    movzx   ecx, si
    cmp     eax, ecx
    jae     .done
    mov     eax, ecx
.done:
    movzx   eax, ax
    ret

global umath_bit16_min_u
umath_bit16_min_u:
    movzx   eax, di
    movzx   ecx, si
    cmp     eax, ecx
    jbe     .done
    mov     eax, ecx
.done:
    movzx   eax, ax
    ret

global umath_bit16_abs_s
umath_bit16_abs_s:
    movsx   eax, di
    test    eax, eax
    jge     .done
    neg     eax
    cmp     eax, 32768
    jne     .done
    mov     eax, 32767
.done:
    movzx   eax, ax
    ret

global umath_bit16_sign_extend32
umath_bit16_sign_extend32:
    movsx   eax, di
    ret

global umath_bit16_sign_extend64
umath_bit16_sign_extend64:
    movsx   rax, di
    ret

global umath_bit16_zero_extend32
umath_bit16_zero_extend32:
    movzx   eax, di
    ret

global umath_bit16_zero_extend64
umath_bit16_zero_extend64:
    movzx   rax, di
    ret

global umath_bit16_cmp_s
umath_bit16_cmp_s:
    movsx   eax, di
    movsx   ecx, si
    cmp     eax, ecx
    je      .eq
    jl      .lt
    mov     eax, 1
    ret
.eq: xor eax, eax
     ret
.lt: mov eax, -1
     ret

global umath_bit16_cmp_u
umath_bit16_cmp_u:
    movzx   eax, di
    movzx   ecx, si
    cmp     eax, ecx
    je      .eq
    jb      .lt
    mov     eax, 1
    ret
.eq: xor eax, eax
     ret
.lt: mov eax, -1
     ret

; =============================================================================
; FP16 bit field operations
; layout: [15]=sign [14:10]=exponent(5) [9:0]=mantissa(10)
; =============================================================================

; -----------------------------------------------------------------------------
; umath_bit16_fp16_sign - extract sign bit
; args: di = fp16 bits   returns: eax = 0/1
; -----------------------------------------------------------------------------
global umath_bit16_fp16_sign
umath_bit16_fp16_sign:
    movzx   eax, di
    shr     eax, 15
    and     eax, 1
    ret

; -----------------------------------------------------------------------------
; umath_bit16_fp16_exponent - extract raw 5-bit exponent (biased, bias=15)
; args: di = fp16 bits   returns: eax = exponent (0-31)
; -----------------------------------------------------------------------------
global umath_bit16_fp16_exponent
umath_bit16_fp16_exponent:
    movzx   eax, di
    shr     eax, 10
    and     eax, 0x1F
    ret

; -----------------------------------------------------------------------------
; umath_bit16_fp16_mantissa - extract 10-bit mantissa
; args: di = fp16 bits   returns: eax = mantissa (0-1023)
; -----------------------------------------------------------------------------
global umath_bit16_fp16_mantissa
umath_bit16_fp16_mantissa:
    movzx   eax, di
    and     eax, 0x3FF
    ret

; -----------------------------------------------------------------------------
; umath_bit16_fp16_compose - build fp16 bits from sign/exp/mantissa
; args: edi=sign(0/1), esi=exponent(0-31), edx=mantissa(0-1023)
; returns: eax = fp16 bits (zero-extended)
; -----------------------------------------------------------------------------
global umath_bit16_fp16_compose
umath_bit16_fp16_compose:
    mov     eax, edi
    and     eax, 1
    shl     eax, 15
    mov     ecx, esi
    and     ecx, 0x1F
    shl     ecx, 10
    or      eax, ecx
    mov     ecx, edx
    and     ecx, 0x3FF
    or      eax, ecx
    movzx   eax, ax
    ret

; -----------------------------------------------------------------------------
; umath_bit16_fp16_is_nan - check NaN (exp=31, mantissa!=0)
; args: di = fp16 bits   returns: eax = 0/1
; -----------------------------------------------------------------------------
global umath_bit16_fp16_is_nan
umath_bit16_fp16_is_nan:
    movzx   eax, di
    and     eax, 0x7FFF             ; clear sign
    cmp     eax, 0x7C00              ; exp=31, mant=0 -> exactly inf
    jbe     .check_le
    cmp     eax, 0x7FFF
    jbe     .is_nan
.check_le:
    cmp     eax, 0x7C00
    ja      .is_nan
    xor     eax, eax
    ret
.is_nan:
    ; only NaN if > 0x7C00 (exp all 1s and mantissa != 0)
    movzx   eax, di
    and     eax, 0x7FFF
    cmp     eax, 0x7C00
    jbe     .no
    mov     eax, 1
    ret
.no:
    xor     eax, eax
    ret

; -----------------------------------------------------------------------------
; umath_bit16_fp16_is_inf - check +/-infinity (exp=31, mantissa=0)
; args: di = fp16 bits   returns: eax = 0/1
; -----------------------------------------------------------------------------
global umath_bit16_fp16_is_inf
umath_bit16_fp16_is_inf:
    movzx   eax, di
    and     eax, 0x7FFF
    cmp     eax, 0x7C00
    sete    al
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_bit16_fp16_is_zero - check +/-zero (exp=0, mantissa=0)
; args: di = fp16 bits   returns: eax = 0/1
; -----------------------------------------------------------------------------
global umath_bit16_fp16_is_zero
umath_bit16_fp16_is_zero:
    movzx   eax, di
    and     eax, 0x7FFF
    test    eax, eax
    setz    al
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_bit16_fp16_flip_sign - flip sign bit
; args: di = fp16 bits   returns: ax = fp16 bits with sign flipped
; -----------------------------------------------------------------------------
global umath_bit16_fp16_flip_sign
umath_bit16_fp16_flip_sign:
    mov     ax, di
    xor     ax, 0x8000
    ret

; -----------------------------------------------------------------------------
; umath_bit16_fp16_abs - clear sign bit
; args: di = fp16 bits   returns: ax = fp16 bits with sign cleared
; -----------------------------------------------------------------------------
global umath_bit16_fp16_abs
umath_bit16_fp16_abs:
    mov     ax, di
    and     ax, 0x7FFF
    ret

; =============================================================================
; BF16 bit field operations
; layout: [15]=sign [14:7]=exponent(8) [6:0]=mantissa(7)
; =============================================================================

; -----------------------------------------------------------------------------
; umath_bit16_bf16_sign - extract sign bit
; args: di = bf16 bits   returns: eax = 0/1
; -----------------------------------------------------------------------------
global umath_bit16_bf16_sign
umath_bit16_bf16_sign:
    movzx   eax, di
    shr     eax, 15
    and     eax, 1
    ret

; -----------------------------------------------------------------------------
; umath_bit16_bf16_exponent - extract raw 8-bit exponent (biased, bias=127)
; args: di = bf16 bits   returns: eax = exponent (0-255)
; -----------------------------------------------------------------------------
global umath_bit16_bf16_exponent
umath_bit16_bf16_exponent:
    movzx   eax, di
    shr     eax, 7
    and     eax, 0xFF
    ret

; -----------------------------------------------------------------------------
; umath_bit16_bf16_mantissa - extract 7-bit mantissa
; args: di = bf16 bits   returns: eax = mantissa (0-127)
; -----------------------------------------------------------------------------
global umath_bit16_bf16_mantissa
umath_bit16_bf16_mantissa:
    movzx   eax, di
    and     eax, 0x7F
    ret

; -----------------------------------------------------------------------------
; umath_bit16_bf16_compose - build bf16 bits from sign/exp/mantissa
; args: edi=sign(0/1), esi=exponent(0-255), edx=mantissa(0-127)
; returns: eax = bf16 bits (zero-extended)
; -----------------------------------------------------------------------------
global umath_bit16_bf16_compose
umath_bit16_bf16_compose:
    mov     eax, edi
    and     eax, 1
    shl     eax, 15
    mov     ecx, esi
    and     ecx, 0xFF
    shl     ecx, 7
    or      eax, ecx
    mov     ecx, edx
    and     ecx, 0x7F
    or      eax, ecx
    movzx   eax, ax
    ret

; -----------------------------------------------------------------------------
; umath_bit16_bf16_is_nan - check NaN (exp=255, mantissa!=0)
; args: di = bf16 bits   returns: eax = 0/1
; -----------------------------------------------------------------------------
global umath_bit16_bf16_is_nan
umath_bit16_bf16_is_nan:
    movzx   eax, di
    and     eax, 0x7FFF
    cmp     eax, 0x7F80              ; exp=255, mant=0 -> inf
    jbe     .no
    mov     eax, 1
    ret
.no:
    xor     eax, eax
    ret

; -----------------------------------------------------------------------------
; umath_bit16_bf16_is_inf - check +/-infinity (exp=255, mantissa=0)
; args: di = bf16 bits   returns: eax = 0/1
; -----------------------------------------------------------------------------
global umath_bit16_bf16_is_inf
umath_bit16_bf16_is_inf:
    movzx   eax, di
    and     eax, 0x7FFF
    cmp     eax, 0x7F80
    sete    al
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_bit16_bf16_is_zero - check +/-zero (exp=0, mantissa=0)
; args: di = bf16 bits   returns: eax = 0/1
; -----------------------------------------------------------------------------
global umath_bit16_bf16_is_zero
umath_bit16_bf16_is_zero:
    movzx   eax, di
    and     eax, 0x7FFF
    test    eax, eax
    setz    al
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_bit16_bf16_flip_sign - flip sign bit
; args: di = bf16 bits   returns: ax = bf16 bits with sign flipped
; -----------------------------------------------------------------------------
global umath_bit16_bf16_flip_sign
umath_bit16_bf16_flip_sign:
    mov     ax, di
    xor     ax, 0x8000
    ret

; -----------------------------------------------------------------------------
; umath_bit16_bf16_abs - clear sign bit
; args: di = bf16 bits   returns: ax = bf16 bits with sign cleared
; -----------------------------------------------------------------------------
global umath_bit16_bf16_abs
umath_bit16_bf16_abs:
    mov     ax, di
    and     ax, 0x7FFF
    ret