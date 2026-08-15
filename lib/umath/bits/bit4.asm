%ifndef GUARD_LIB_UMATH_BITS_BIT4_ASM
%define GUARD_LIB_UMATH_BITS_BIT4_ASM
; =============================================================================
; umath - unified math library
; bits/bit4.asm - nibble / INT4 / UINT4 operations
; =============================================================================
; used for: INT4/UINT4 quantization (GPTQ, AWQ), Q4_0/Q4_1, MXFP4/NVFP4 packing
;
; layout convention: two 4-bit elements packed per byte
;   element 0 = low nibble  (bits 3:0)
;   element 1 = high nibble (bits 7:4)
;
; functions:
;   umath_bit4_pack          (lo, hi -> packed byte)
;   umath_bit4_unpack_lo     (packed -> low nibble, 0-15)
;   umath_bit4_unpack_hi     (packed -> high nibble, 0-15)
;   umath_bit4_swap          (packed -> byte with nibbles swapped)
;   umath_bit4_sign_extend   (nibble -> sign-extended i64, INT4 semantics)
;   umath_bit4_zero_extend   (nibble -> zero-extended u64, UINT4 semantics)
;   umath_bit4_add_sat_s     (a, b -> saturating signed INT4 add, [-8,7])
;   umath_bit4_add_sat_u     (a, b -> saturating unsigned UINT4 add, [0,15])
;   umath_bit4_sub_sat_s     (a, b -> saturating signed INT4 sub)
;   umath_bit4_sub_sat_u     (a, b -> saturating unsigned UINT4 sub)
;   umath_bit4_max_s         (a, b -> max, signed INT4)
;   umath_bit4_min_s         (a, b -> min, signed INT4)
;   umath_bit4_max_u         (a, b -> max, unsigned UINT4)
;   umath_bit4_min_u         (a, b -> min, unsigned UINT4)
;   umath_bit4_abs_s         (a -> |a|, signed INT4, clamps -8 -> 7)
;   umath_bit4_popcount      (nibble -> popcount, 0-4)
;   umath_bit4_to_i8         (nibble -> sign-extended i8)
;   umath_bit4_from_i8       (i8 -> clamped nibble [-8,7] as 4-bit)
; =============================================================================

bits 64
section .text

; -----------------------------------------------------------------------------
; umath_bit4_pack - pack two nibbles into one byte
; args:    dil = lo (element 0, low nibble, only low 4 bits used)
;          sil = hi (element 1, high nibble, only low 4 bits used)
; returns: al  = packed byte
; -----------------------------------------------------------------------------
global umath_bit4_pack
umath_bit4_pack:
    mov     al, dil
    and     al, 0x0F
    mov     ah, sil
    and     ah, 0x0F
    shl     ah, 4
    or      al, ah
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_bit4_unpack_lo - extract low nibble (element 0)
; args:    dil = packed byte
; returns: al  = low nibble (0-15, raw bits, no sign extension)
; -----------------------------------------------------------------------------
global umath_bit4_unpack_lo
umath_bit4_unpack_lo:
    mov     al, dil
    and     al, 0x0F
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_bit4_unpack_hi - extract high nibble (element 1)
; args:    dil = packed byte
; returns: al  = high nibble (0-15, raw bits, no sign extension)
; -----------------------------------------------------------------------------
global umath_bit4_unpack_hi
umath_bit4_unpack_hi:
    mov     al, dil
    shr     al, 4
    and     al, 0x0F
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_bit4_swap - swap the two nibbles within a byte
; args:    dil = packed byte
; returns: al  = byte with nibbles swapped
; -----------------------------------------------------------------------------
global umath_bit4_swap
umath_bit4_swap:
    mov     al, dil
    rol     al, 4
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_bit4_sign_extend - sign extend 4-bit value (INT4) to i64
; args:    dil = raw nibble (0-15)
; returns: rax = sign-extended i64
; example: 0xF (1111 = -1) -> 0xFFFFFFFFFFFFFFFF
;          0x7 (0111 = +7) -> 0x0000000000000007
;          0x8 (1000 = -8) -> 0xFFFFFFFFFFFFFFF8
; -----------------------------------------------------------------------------
global umath_bit4_sign_extend
umath_bit4_sign_extend:
    mov     al, dil
    and     al, 0x0F
    shl     al, 4           ; move nibble to top of byte
    movsx   rax, al         ; sign-extend from bit 7 (now = original bit 3)
    sar     rax, 4          ; shift back down, preserving sign
    ret

; -----------------------------------------------------------------------------
; umath_bit4_zero_extend - zero extend 4-bit value (UINT4) to u64
; args:    dil = raw nibble (0-15)
; returns: rax = zero-extended u64 (0-15)
; -----------------------------------------------------------------------------
global umath_bit4_zero_extend
umath_bit4_zero_extend:
    mov     al, dil
    and     al, 0x0F
    movzx   rax, al
    ret

; -----------------------------------------------------------------------------
; umath_bit4_add_sat_s - saturating signed INT4 add, clamp to [-8, 7]
; args:    dil = a (raw nibble, INT4)
;          sil = b (raw nibble, INT4)
; returns: al  = result nibble (raw 4-bit, saturated)
; -----------------------------------------------------------------------------
global umath_bit4_add_sat_s
umath_bit4_add_sat_s:
    push    rbx
    mov     dil, dil
    call    umath_bit4_sign_extend_local
    mov     ebx, eax        ; a_ext
    mov     dil, sil
    call    umath_bit4_sign_extend_local
    add     eax, ebx        ; a+b (full precision)
    cmp     eax, 7
    jg      .sat_max
    cmp     eax, -8
    jl      .sat_min
    jmp     .pack
.sat_max:
    mov     eax, 7
    jmp     .pack
.sat_min:
    mov     eax, -8
.pack:
    and     al, 0x0F
    movzx   eax, al
    pop     rbx
    ret

; local helper: sign extend dil nibble to eax (i32)
umath_bit4_sign_extend_local:
    mov     al, dil
    and     al, 0x0F
    shl     al, 4
    movsx   eax, al
    sar     eax, 4
    ret

; -----------------------------------------------------------------------------
; umath_bit4_add_sat_u - saturating unsigned UINT4 add, clamp to [0, 15]
; args:    dil = a (0-15)
;          sil = b (0-15)
; returns: al  = result (0-15, saturated)
; -----------------------------------------------------------------------------
global umath_bit4_add_sat_u
umath_bit4_add_sat_u:
    mov     al, dil
    and     al, 0x0F
    mov     cl, sil
    and     cl, 0x0F
    add     al, cl
    cmp     al, 15
    jbe     .done
    mov     al, 15
.done:
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_bit4_sub_sat_s - saturating signed INT4 sub, clamp to [-8, 7]
; args:    dil = a (raw nibble, INT4)
;          sil = b (raw nibble, INT4)
; returns: al  = result nibble (raw 4-bit, saturated)
; -----------------------------------------------------------------------------
global umath_bit4_sub_sat_s
umath_bit4_sub_sat_s:
    push    rbx
    call    umath_bit4_sign_extend_local   ; dil -> eax = a_ext
    mov     ebx, eax
    mov     dil, sil
    call    umath_bit4_sign_extend_local   ; sil -> eax = b_ext
    mov     ecx, eax
    mov     eax, ebx
    sub     eax, ecx
    cmp     eax, 7
    jg      .sat_max
    cmp     eax, -8
    jl      .sat_min
    jmp     .pack
.sat_max:
    mov     eax, 7
    jmp     .pack
.sat_min:
    mov     eax, -8
.pack:
    and     al, 0x0F
    movzx   eax, al
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; umath_bit4_sub_sat_u - saturating unsigned UINT4 sub, clamp to [0, 15]
; args:    dil = a (0-15)
;          sil = b (0-15)
; returns: al  = result (0-15, saturated; 0 if a<b)
; -----------------------------------------------------------------------------
global umath_bit4_sub_sat_u
umath_bit4_sub_sat_u:
    mov     al, dil
    and     al, 0x0F
    mov     cl, sil
    and     cl, 0x0F
    cmp     al, cl
    jae     .sub
    xor     eax, eax
    ret
.sub:
    sub     al, cl
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_bit4_max_s - max of two signed INT4 values
; args:    dil = a (raw nibble), sil = b (raw nibble)
; returns: al  = max value (raw 4-bit)
; -----------------------------------------------------------------------------
global umath_bit4_max_s
umath_bit4_max_s:
    push    rbx
    call    umath_bit4_sign_extend_local
    mov     ebx, eax
    mov     dil, sil
    call    umath_bit4_sign_extend_local
    cmp     ebx, eax
    jge     .a_wins
    jmp     .pack
.a_wins:
    mov     eax, ebx
.pack:
    and     al, 0x0F
    movzx   eax, al
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; umath_bit4_min_s - min of two signed INT4 values
; args:    dil = a (raw nibble), sil = b (raw nibble)
; returns: al  = min value (raw 4-bit)
; -----------------------------------------------------------------------------
global umath_bit4_min_s
umath_bit4_min_s:
    push    rbx
    call    umath_bit4_sign_extend_local
    mov     ebx, eax
    mov     dil, sil
    call    umath_bit4_sign_extend_local
    cmp     ebx, eax
    jle     .a_wins
    jmp     .pack
.a_wins:
    mov     eax, ebx
.pack:
    and     al, 0x0F
    movzx   eax, al
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; umath_bit4_max_u - max of two unsigned UINT4 values
; args:    dil = a (0-15), sil = b (0-15)
; returns: al  = max(a,b)
; -----------------------------------------------------------------------------
global umath_bit4_max_u
umath_bit4_max_u:
    mov     al, dil
    and     al, 0x0F
    mov     cl, sil
    and     cl, 0x0F
    cmp     al, cl
    jae     .done
    mov     al, cl
.done:
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_bit4_min_u - min of two unsigned UINT4 values
; args:    dil = a (0-15), sil = b (0-15)
; returns: al  = min(a,b)
; -----------------------------------------------------------------------------
global umath_bit4_min_u
umath_bit4_min_u:
    mov     al, dil
    and     al, 0x0F
    mov     cl, sil
    and     cl, 0x0F
    cmp     al, cl
    jbe     .done
    mov     al, cl
.done:
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_bit4_abs_s - absolute value of signed INT4, saturate -8 -> 7
; args:    dil = a (raw nibble, INT4)
; returns: al  = |a| as raw 4-bit (7 if input was -8, since +8 doesn't fit)
; -----------------------------------------------------------------------------
global umath_bit4_abs_s
umath_bit4_abs_s:
    call    umath_bit4_sign_extend_local   ; eax = sign-extended value
    test    eax, eax
    jge     .pack
    neg     eax
    cmp     eax, 8
    jne     .pack
    mov     eax, 7          ; saturate: abs(-8) = 8 doesn't fit in INT4
.pack:
    and     al, 0x0F
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_bit4_popcount - count set bits in nibble
; args:    dil = nibble (0-15)
; returns: eax = popcount (0-4)
; -----------------------------------------------------------------------------
global umath_bit4_popcount
umath_bit4_popcount:
    movzx   eax, dil
    and     eax, 0x0F
    popcnt  eax, eax
    ret

; -----------------------------------------------------------------------------
; umath_bit4_to_i8 - sign-extend nibble to i8 (returned zero-extended in eax)
; args:    dil = raw nibble (0-15)
; returns: eax = i8 value, sign-extended into low byte
;          (caller should treat al as signed i8)
; -----------------------------------------------------------------------------
global umath_bit4_to_i8
umath_bit4_to_i8:
    mov     al, dil
    and     al, 0x0F
    shl     al, 4
    sar     al, 4           ; arithmetic shift preserves sign
    movsx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_bit4_from_i8 - clamp i8 value into INT4 range and pack to nibble
; args:    dil = i8 value (signed, passed as byte)
; returns: al  = clamped raw nibble (4-bit, range [-8,7] encoded)
; -----------------------------------------------------------------------------
global umath_bit4_from_i8
umath_bit4_from_i8:
    movsx   eax, dil
    cmp     eax, 7
    jg      .sat_max
    cmp     eax, -8
    jl      .sat_min
    jmp     .pack
.sat_max:
    mov     eax, 7
    jmp     .pack
.sat_min:
    mov     eax, -8
.pack:
    and     al, 0x0F
    movzx   eax, al
    ret
%endif ; GUARD_LIB_UMATH_BITS_BIT4_ASM
