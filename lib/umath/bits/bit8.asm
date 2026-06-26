; =============================================================================
; umath - unified math library
; bits/bit8.asm - byte-level operations (INT8, UINT8, FP8 bit manipulation)
; =============================================================================
; functions:
;   umath_bit8_rotl          (val, amount -> rotated byte)
;   umath_bit8_rotr          (val, amount -> rotated byte)
;   umath_bit8_swap_nibbles  (val -> byte with nibbles swapped)
;   umath_bit8_reverse_in16  (word -> byte order reversed within 16 bits)
;   umath_bit8_reverse_in32  (dword -> byte order reversed within 32 bits)
;   umath_bit8_add_sat_s     (a, b -> saturating signed INT8 add)
;   umath_bit8_add_sat_u     (a, b -> saturating unsigned UINT8 add)
;   umath_bit8_sub_sat_s     (a, b -> saturating signed INT8 sub)
;   umath_bit8_sub_sat_u     (a, b -> saturating unsigned UINT8 sub)
;   umath_bit8_max_s         (a, b -> signed max)
;   umath_bit8_min_s         (a, b -> signed min)
;   umath_bit8_max_u         (a, b -> unsigned max)
;   umath_bit8_min_u         (a, b -> unsigned min)
;   umath_bit8_abs_s         (a -> |a|, saturate -128 -> 127)
;   umath_bit8_sign_extend16 (i8 -> i16)
;   umath_bit8_sign_extend32 (i8 -> i32)
;   umath_bit8_sign_extend64 (i8 -> i64)
;   umath_bit8_zero_extend16 (u8 -> u16)
;   umath_bit8_zero_extend32 (u8 -> u32)
;   umath_bit8_zero_extend64 (u8 -> u64)
;   umath_bit8_cmp_s         (a, b -> -1/0/1, signed)
;   umath_bit8_cmp_u         (a, b -> -1/0/1, unsigned)
;   umath_bit8_parity        (val -> 0/1, parity bit)
;   umath_bit8_fp8_sign      (fp8 -> sign bit, 0/1)
;   umath_bit8_fp8_flip_sign (fp8 -> fp8 with sign flipped)
;   umath_bit8_fp8_abs       (fp8 -> fp8 with sign cleared)
; =============================================================================

bits 64
section .text

; -----------------------------------------------------------------------------
; umath_bit8_rotl - rotate byte left
; args:    dil = val, sil = amount (0-7, masked)
; returns: al  = rotated byte
; -----------------------------------------------------------------------------
global umath_bit8_rotl
umath_bit8_rotl:
    mov     al, dil
    mov     cl, sil
    and     cl, 7
    rol     al, cl
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_bit8_rotr - rotate byte right
; args:    dil = val, sil = amount (0-7, masked)
; returns: al  = rotated byte
; -----------------------------------------------------------------------------
global umath_bit8_rotr
umath_bit8_rotr:
    mov     al, dil
    mov     cl, sil
    and     cl, 7
    ror     al, cl
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_bit8_swap_nibbles - swap high/low nibbles of a byte
; args:    dil = val
; returns: al  = byte with nibbles swapped
; -----------------------------------------------------------------------------
global umath_bit8_swap_nibbles
umath_bit8_swap_nibbles:
    mov     al, dil
    rol     al, 4
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_bit8_reverse_in16 - reverse byte order within a 16-bit value
; args:    di = val
; returns: ax = byte-reversed
; -----------------------------------------------------------------------------
global umath_bit8_reverse_in16
umath_bit8_reverse_in16:
    mov     ax, di
    rol     ax, 8
    ret

; -----------------------------------------------------------------------------
; umath_bit8_reverse_in32 - reverse byte order within a 32-bit value
; args:    edi = val
; returns: eax = byte-reversed (BSWAP)
; -----------------------------------------------------------------------------
global umath_bit8_reverse_in32
umath_bit8_reverse_in32:
    mov     eax, edi
    bswap   eax
    ret

; -----------------------------------------------------------------------------
; umath_bit8_add_sat_s - saturating signed INT8 add, clamp to [-128,127]
; args:    dil = a (i8), sil = b (i8)
; returns: al  = saturated result
; -----------------------------------------------------------------------------
global umath_bit8_add_sat_s
umath_bit8_add_sat_s:
    movsx   eax, dil
    movsx   ecx, sil
    add     eax, ecx
    cmp     eax, 127
    jg      .sat_max
    cmp     eax, -128
    jl      .sat_min
    jmp     .pack
.sat_max:
    mov     eax, 127
    jmp     .pack
.sat_min:
    mov     eax, -128
.pack:
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_bit8_add_sat_u - saturating unsigned UINT8 add, clamp to [0,255]
; args:    dil = a (u8), sil = b (u8)
; returns: al  = saturated result
; -----------------------------------------------------------------------------
global umath_bit8_add_sat_u
umath_bit8_add_sat_u:
    movzx   eax, dil
    movzx   ecx, sil
    add     eax, ecx
    cmp     eax, 255
    jbe     .done
    mov     eax, 255
.done:
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_bit8_sub_sat_s - saturating signed INT8 sub, clamp to [-128,127]
; args:    dil = a (i8), sil = b (i8)
; returns: al  = saturated result
; -----------------------------------------------------------------------------
global umath_bit8_sub_sat_s
umath_bit8_sub_sat_s:
    movsx   eax, dil
    movsx   ecx, sil
    sub     eax, ecx
    cmp     eax, 127
    jg      .sat_max
    cmp     eax, -128
    jl      .sat_min
    jmp     .pack
.sat_max:
    mov     eax, 127
    jmp     .pack
.sat_min:
    mov     eax, -128
.pack:
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_bit8_sub_sat_u - saturating unsigned UINT8 sub, clamp to [0,255]
; args:    dil = a (u8), sil = b (u8)
; returns: al  = saturated result (0 if a<b)
; -----------------------------------------------------------------------------
global umath_bit8_sub_sat_u
umath_bit8_sub_sat_u:
    movzx   eax, dil
    movzx   ecx, sil
    cmp     eax, ecx
    jae     .sub
    xor     eax, eax
    ret
.sub:
    sub     eax, ecx
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_bit8_max_s - signed INT8 max
; args:    dil = a (i8), sil = b (i8)
; returns: al  = max(a,b) signed
; -----------------------------------------------------------------------------
global umath_bit8_max_s
umath_bit8_max_s:
    movsx   eax, dil
    movsx   ecx, sil
    cmp     eax, ecx
    jge     .done
    mov     eax, ecx
.done:
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_bit8_min_s - signed INT8 min
; args:    dil = a (i8), sil = b (i8)
; returns: al  = min(a,b) signed
; -----------------------------------------------------------------------------
global umath_bit8_min_s
umath_bit8_min_s:
    movsx   eax, dil
    movsx   ecx, sil
    cmp     eax, ecx
    jle     .done
    mov     eax, ecx
.done:
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_bit8_max_u - unsigned UINT8 max
; args:    dil = a (u8), sil = b (u8)
; returns: al  = max(a,b) unsigned
; -----------------------------------------------------------------------------
global umath_bit8_max_u
umath_bit8_max_u:
    movzx   eax, dil
    movzx   ecx, sil
    cmp     eax, ecx
    jae     .done
    mov     eax, ecx
.done:
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_bit8_min_u - unsigned UINT8 min
; args:    dil = a (u8), sil = b (u8)
; returns: al  = min(a,b) unsigned
; -----------------------------------------------------------------------------
global umath_bit8_min_u
umath_bit8_min_u:
    movzx   eax, dil
    movzx   ecx, sil
    cmp     eax, ecx
    jbe     .done
    mov     eax, ecx
.done:
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_bit8_abs_s - absolute value of signed INT8, saturate -128 -> 127
; args:    dil = a (i8)
; returns: al  = |a|, saturated
; -----------------------------------------------------------------------------
global umath_bit8_abs_s
umath_bit8_abs_s:
    movsx   eax, dil
    test    eax, eax
    jge     .done
    neg     eax
    cmp     eax, 128
    jne     .done
    mov     eax, 127       ; saturate: abs(-128) = 128 doesn't fit
.done:
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_bit8_sign_extend16 - sign extend i8 to i16
; args:    dil = a (i8)
; returns: ax  = sign-extended i16
; -----------------------------------------------------------------------------
global umath_bit8_sign_extend16
umath_bit8_sign_extend16:
    movsx   ax, dil
    ret

; -----------------------------------------------------------------------------
; umath_bit8_sign_extend32 - sign extend i8 to i32
; args:    dil = a (i8)
; returns: eax = sign-extended i32
; -----------------------------------------------------------------------------
global umath_bit8_sign_extend32
umath_bit8_sign_extend32:
    movsx   eax, dil
    ret

; -----------------------------------------------------------------------------
; umath_bit8_sign_extend64 - sign extend i8 to i64
; args:    dil = a (i8)
; returns: rax = sign-extended i64
; -----------------------------------------------------------------------------
global umath_bit8_sign_extend64
umath_bit8_sign_extend64:
    movsx   rax, dil
    ret

; -----------------------------------------------------------------------------
; umath_bit8_zero_extend16 - zero extend u8 to u16
; args:    dil = a (u8)
; returns: ax  = zero-extended u16
; -----------------------------------------------------------------------------
global umath_bit8_zero_extend16
umath_bit8_zero_extend16:
    movzx   ax, dil
    ret

; -----------------------------------------------------------------------------
; umath_bit8_zero_extend32 - zero extend u8 to u32
; args:    dil = a (u8)
; returns: eax = zero-extended u32
; -----------------------------------------------------------------------------
global umath_bit8_zero_extend32
umath_bit8_zero_extend32:
    movzx   eax, dil
    ret

; -----------------------------------------------------------------------------
; umath_bit8_zero_extend64 - zero extend u8 to u64
; args:    dil = a (u8)
; returns: rax = zero-extended u64
; -----------------------------------------------------------------------------
global umath_bit8_zero_extend64
umath_bit8_zero_extend64:
    movzx   rax, dil
    ret

; -----------------------------------------------------------------------------
; umath_bit8_cmp_s - signed byte comparison
; args:    dil = a (i8), sil = b (i8)
; returns: eax = -1 if a<b, 0 if equal, 1 if a>b
; -----------------------------------------------------------------------------
global umath_bit8_cmp_s
umath_bit8_cmp_s:
    movsx   eax, dil
    movsx   ecx, sil
    cmp     eax, ecx
    je      .eq
    jl      .lt
    mov     eax, 1
    ret
.eq:
    xor     eax, eax
    ret
.lt:
    mov     eax, -1
    ret

; -----------------------------------------------------------------------------
; umath_bit8_cmp_u - unsigned byte comparison
; args:    dil = a (u8), sil = b (u8)
; returns: eax = -1 if a<b, 0 if equal, 1 if a>b
; -----------------------------------------------------------------------------
global umath_bit8_cmp_u
umath_bit8_cmp_u:
    movzx   eax, dil
    movzx   ecx, sil
    cmp     eax, ecx
    je      .eq
    jb      .lt
    mov     eax, 1
    ret
.eq:
    xor     eax, eax
    ret
.lt:
    mov     eax, -1
    ret

; -----------------------------------------------------------------------------
; umath_bit8_parity - compute parity bit of byte (1 if odd number of 1-bits)
; args:    dil = val
; returns: eax = 0 or 1
; -----------------------------------------------------------------------------
global umath_bit8_parity
umath_bit8_parity:
    movzx   eax, dil
    popcnt  eax, eax
    and     eax, 1
    ret

; -----------------------------------------------------------------------------
; umath_bit8_fp8_sign - extract sign bit from FP8 value (bit 7)
; args:    dil = fp8 bits
; returns: eax = sign bit (0 or 1)
; -----------------------------------------------------------------------------
global umath_bit8_fp8_sign
umath_bit8_fp8_sign:
    movzx   eax, dil
    shr     eax, 7
    and     eax, 1
    ret

; -----------------------------------------------------------------------------
; umath_bit8_fp8_flip_sign - flip sign bit of FP8 value
; args:    dil = fp8 bits
; returns: al  = fp8 bits with sign bit flipped
; -----------------------------------------------------------------------------
global umath_bit8_fp8_flip_sign
umath_bit8_fp8_flip_sign:
    mov     al, dil
    xor     al, 0x80
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_bit8_fp8_abs - clear sign bit of FP8 value (absolute value)
; args:    dil = fp8 bits
; returns: al  = fp8 bits with sign bit cleared
; -----------------------------------------------------------------------------
global umath_bit8_fp8_abs
umath_bit8_fp8_abs:
    mov     al, dil
    and     al, 0x7F
    movzx   eax, al
    ret