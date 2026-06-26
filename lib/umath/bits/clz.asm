; =============================================================================
; umath - unified math library
; bits/clz.asm - count leading zeros
; =============================================================================
; functions:
;   umath_clz8  (u8  -> u8)
;   umath_clz16 (u16 -> u16)
;   umath_clz32 (u32 -> u32)
;   umath_clz64 (u64 -> u64)
;
; args:    rdi = value
; returns: rax = leading zero count
;          returns full bit width if input is 0
; =============================================================================

bits 64
section .text

; -----------------------------------------------------------------------------
; umath_clz8 - count leading zeros in 8-bit value
; args:    dil = value (u8)
; returns: al  = clz result (0-8)
; -----------------------------------------------------------------------------
global umath_clz8
umath_clz8:
    movzx   edi, dil                ; zero extend to 32 bits
    test    edi, edi
    jz      .zero8
    lzcnt   eax, edi                ; lzcnt on 32-bit
    sub     eax, 24                 ; adjust for 8-bit width
    ret
.zero8:
    mov     eax, 8
    ret

; -----------------------------------------------------------------------------
; umath_clz16 - count leading zeros in 16-bit value
; args:    di  = value (u16)
; returns: ax  = clz result (0-16)
; -----------------------------------------------------------------------------
global umath_clz16
umath_clz16:
    movzx   edi, di                 ; zero extend to 32 bits
    test    edi, edi
    jz      .zero16
    lzcnt   eax, edi
    sub     eax, 16                 ; adjust for 16-bit width
    ret
.zero16:
    mov     eax, 16
    ret

; -----------------------------------------------------------------------------
; umath_clz32 - count leading zeros in 32-bit value
; args:    edi = value (u32)
; returns: eax = clz result (0-32)
; -----------------------------------------------------------------------------
global umath_clz32
umath_clz32:
    test    edi, edi
    jz      .zero32
    lzcnt   eax, edi
    ret
.zero32:
    mov     eax, 32
    ret

; -----------------------------------------------------------------------------
; umath_clz64 - count leading zeros in 64-bit value
; args:    rdi = value (u64)
; returns: rax = clz result (0-64)
; -----------------------------------------------------------------------------
global umath_clz64
umath_clz64:
    test    rdi, rdi
    jz      .zero64
    lzcnt   rax, rdi
    ret
.zero64:
    mov     rax, 64
    ret

; -----------------------------------------------------------------------------
; umath_clz32_bsr - BSR fallback for CPUs without LZCNT
; args:    edi = value (u32)
; returns: eax = clz result (0-32)
; note:    use only when LZCNT unavailable
; -----------------------------------------------------------------------------
global umath_clz32_bsr
umath_clz32_bsr:
    test    edi, edi
    jz      .zero_bsr32
    bsr     eax, edi                ; eax = position of highest set bit
    xor     eax, 31                 ; clz = 31 - bsr
    ret
.zero_bsr32:
    mov     eax, 32
    ret

; -----------------------------------------------------------------------------
; umath_clz64_bsr - BSR fallback for CPUs without LZCNT
; args:    rdi = value (u64)
; returns: rax = clz result (0-64)
; note:    use only when LZCNT unavailable
; -----------------------------------------------------------------------------
global umath_clz64_bsr
umath_clz64_bsr:
    test    rdi, rdi
    jz      .zero_bsr64
    bsr     rax, rdi
    xor     rax, 63                 ; clz = 63 - bsr
    ret
.zero_bsr64:
    mov     rax, 64
    ret