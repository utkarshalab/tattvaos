%ifndef GUARD_LIB_UMATH_BITS_BIT1_ASM
%define GUARD_LIB_UMATH_BITS_BIT1_ASM
; =============================================================================
; umath - unified math library
; bits/bit1.asm - single bit / boolean operations
; =============================================================================
; functions:
;   umath_bit1_get        (val, pos -> bit)
;   umath_bit1_set        (val, pos -> val)
;   umath_bit1_clear      (val, pos -> val)
;   umath_bit1_toggle     (val, pos -> val)
;   umath_bit1_test_set   (val, pos -> old_bit, sets bit)
;   umath_bit1_test_clear (val, pos -> old_bit, clears bit)
;   umath_bit1_and        (a, b -> a AND b)
;   umath_bit1_or         (a, b -> a OR b)
;   umath_bit1_xor        (a, b -> a XOR b)
;   umath_bit1_not        (a -> NOT a, masked to 1 bit)
;   umath_bit1_nand       (a, b -> NOT(a AND b))
;   umath_bit1_nor        (a, b -> NOT(a OR b))
;   umath_bit1_xnor       (a, b -> NOT(a XOR b))
;   umath_bit1_to_mask    (bit -> 0x00 or 0xFF)
;   umath_bit1_from_mask  (mask -> 0 or 1)
;
; all single-bit values treated as 0/1 in al/eax/rax
; =============================================================================

bits 64
section .text

; -----------------------------------------------------------------------------
; umath_bit1_get - read bit at position
; args:    rdi = value
;          esi = bit position (0-63)
; returns: rax = 0 or 1
; -----------------------------------------------------------------------------
global umath_bit1_get
umath_bit1_get:
    mov     rax, rdi
    mov     ecx, esi
    shr     rax, cl
    and     rax, 1
    ret

; -----------------------------------------------------------------------------
; umath_bit1_set - set bit at position to 1
; args:    rdi = value
;          esi = bit position
; returns: rax = value with bit set
; -----------------------------------------------------------------------------
global umath_bit1_set
umath_bit1_set:
    mov     rax, rdi
    mov     ecx, esi
    bts     rax, rcx
    ret

; -----------------------------------------------------------------------------
; umath_bit1_clear - clear bit at position to 0
; args:    rdi = value
;          esi = bit position
; returns: rax = value with bit cleared
; -----------------------------------------------------------------------------
global umath_bit1_clear
umath_bit1_clear:
    mov     rax, rdi
    mov     ecx, esi
    btr     rax, rcx
    ret

; -----------------------------------------------------------------------------
; umath_bit1_toggle - toggle bit at position
; args:    rdi = value
;          esi = bit position
; returns: rax = value with bit toggled
; -----------------------------------------------------------------------------
global umath_bit1_toggle
umath_bit1_toggle:
    mov     rax, rdi
    mov     ecx, esi
    btc     rax, rcx
    ret

; -----------------------------------------------------------------------------
; umath_bit1_test_set - test bit then set it (atomic-style sequence, non-locked)
; args:    rdi = value
;          esi = bit position
; returns: rax = old bit value (0/1) in low bit of rax
;          rdx = new value (with bit set)
; -----------------------------------------------------------------------------
global umath_bit1_test_set
umath_bit1_test_set:
    mov     rdx, rdi
    mov     ecx, esi
    bts     rdx, rcx       ; CF = old bit, rdx = new value
    setc    al
    movzx   rax, al
    ret

; -----------------------------------------------------------------------------
; umath_bit1_test_clear - test bit then clear it
; args:    rdi = value
;          esi = bit position
; returns: rax = old bit value (0/1)
;          rdx = new value (with bit cleared)
; -----------------------------------------------------------------------------
global umath_bit1_test_clear
umath_bit1_test_clear:
    mov     rdx, rdi
    mov     ecx, esi
    btr     rdx, rcx       ; CF = old bit, rdx = new value
    setc    al
    movzx   rax, al
    ret

; -----------------------------------------------------------------------------
; umath_bit1_and - logical AND of two single-bit values
; args:    dil = a (0/1)
;          sil = b (0/1)
; returns: al = a AND b
; -----------------------------------------------------------------------------
global umath_bit1_and
umath_bit1_and:
    mov     al, dil
    and     al, sil
    and     al, 1
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_bit1_or - logical OR of two single-bit values
; args:    dil = a (0/1)
;          sil = b (0/1)
; returns: al = a OR b
; -----------------------------------------------------------------------------
global umath_bit1_or
umath_bit1_or:
    mov     al, dil
    or      al, sil
    and     al, 1
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_bit1_xor - logical XOR of two single-bit values
; args:    dil = a (0/1)
;          sil = b (0/1)
; returns: al = a XOR b
; -----------------------------------------------------------------------------
global umath_bit1_xor
umath_bit1_xor:
    mov     al, dil
    xor     al, sil
    and     al, 1
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_bit1_not - logical NOT of single-bit value
; args:    dil = a (0/1)
; returns: al = NOT a (masked to 1 bit)
; -----------------------------------------------------------------------------
global umath_bit1_not
umath_bit1_not:
    mov     al, dil
    xor     al, 1
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_bit1_nand - NOT(a AND b)
; args:    dil = a (0/1)
;          sil = b (0/1)
; returns: al = NAND result
; -----------------------------------------------------------------------------
global umath_bit1_nand
umath_bit1_nand:
    mov     al, dil
    and     al, sil
    xor     al, 1
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_bit1_nor - NOT(a OR b)
; args:    dil = a (0/1)
;          sil = b (0/1)
; returns: al = NOR result
; -----------------------------------------------------------------------------
global umath_bit1_nor
umath_bit1_nor:
    mov     al, dil
    or      al, sil
    xor     al, 1
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_bit1_xnor - NOT(a XOR b)  (i.e. equality)
; args:    dil = a (0/1)
;          sil = b (0/1)
; returns: al = XNOR result (1 if a == b)
; -----------------------------------------------------------------------------
global umath_bit1_xnor
umath_bit1_xnor:
    mov     al, dil
    xor     al, sil
    xor     al, 1
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_bit1_to_mask - expand 0/1 to full byte mask 0x00/0xFF
; args:    dil = bit (0/1)
; returns: al  = 0x00 if bit==0, 0xFF if bit==1
; note:    useful for branchless SIMD blend masks
; -----------------------------------------------------------------------------
global umath_bit1_to_mask
umath_bit1_to_mask:
    mov     al, dil
    and     al, 1
    neg     al             ; 0 -> 0x00, 1 -> 0xFF
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_bit1_from_mask - collapse byte mask to 0/1
; args:    dil = mask byte (0x00 or 0xFF, but any nonzero treated as 1)
; returns: al  = 0 if mask==0, 1 otherwise
; -----------------------------------------------------------------------------
global umath_bit1_from_mask
umath_bit1_from_mask:
    test    dil, dil
    setnz   al
    movzx   eax, al
    ret
%endif ; GUARD_LIB_UMATH_BITS_BIT1_ASM
