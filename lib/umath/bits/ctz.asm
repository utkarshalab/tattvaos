%ifndef GUARD_LIB_UMATH_BITS_CTZ_ASM
%define GUARD_LIB_UMATH_BITS_CTZ_ASM
; =============================================================================
; umath - unified math library
; bits/ctz.asm - count trailing zeros
; =============================================================================
; functions:
;   umath_ctz8  (u8  -> u8)
;   umath_ctz16 (u16 -> u16)
;   umath_ctz32 (u32 -> u32)
;   umath_ctz64 (u64 -> u64)
;
; args:    rdi = value
; returns: rax = trailing zero count
;          returns full bit width if input is 0
; =============================================================================

bits 64
section .text

; -----------------------------------------------------------------------------
; umath_ctz8 - count trailing zeros in 8-bit value
; args:    dil = value (u8)
; returns: al  = ctz result (0-8)
; -----------------------------------------------------------------------------
global umath_ctz8
umath_ctz8:
    movzx   edi, dil
    test    edi, edi
    jz      .zero8
    tzcnt   eax, edi
    ret
.zero8:
    mov     eax, 8
    ret

; -----------------------------------------------------------------------------
; umath_ctz16 - count trailing zeros in 16-bit value
; args:    di  = value (u16)
; returns: ax  = ctz result (0-16)
; -----------------------------------------------------------------------------
global umath_ctz16
umath_ctz16:
    movzx   edi, di
    test    edi, edi
    jz      .zero16
    tzcnt   eax, edi
    ret
.zero16:
    mov     eax, 16
    ret

; -----------------------------------------------------------------------------
; umath_ctz32 - count trailing zeros in 32-bit value
; args:    edi = value (u32)
; returns: eax = ctz result (0-32)
; -----------------------------------------------------------------------------
global umath_ctz32
umath_ctz32:
    test    edi, edi
    jz      .zero32
    tzcnt   eax, edi
    ret
.zero32:
    mov     eax, 32
    ret

; -----------------------------------------------------------------------------
; umath_ctz64 - count trailing zeros in 64-bit value
; args:    rdi = value (u64)
; returns: rax = ctz result (0-64)
; -----------------------------------------------------------------------------
global umath_ctz64
umath_ctz64:
    test    rdi, rdi
    jz      .zero64
    tzcnt   rax, rdi
    ret
.zero64:
    mov     rax, 64
    ret

; -----------------------------------------------------------------------------
; umath_ctz32_bsf - BSF fallback for CPUs without TZCNT
; args:    edi = value (u32)
; returns: eax = ctz result (0-32)
; note:    use only when TZCNT unavailable
; -----------------------------------------------------------------------------
global umath_ctz32_bsf
umath_ctz32_bsf:
    test    edi, edi
    jz      .zero_bsf32
    bsf     eax, edi                ; eax = position of lowest set bit = ctz
    ret
.zero_bsf32:
    mov     eax, 32
    ret

; -----------------------------------------------------------------------------
; umath_ctz64_bsf - BSF fallback for CPUs without TZCNT
; args:    rdi = value (u64)
; returns: rax = ctz result (0-64)
; note:    use only when TZCNT unavailable
; -----------------------------------------------------------------------------
global umath_ctz64_bsf
umath_ctz64_bsf:
    test    rdi, rdi
    jz      .zero_bsf64
    bsf     rax, rdi
    ret
.zero_bsf64:
    mov     rax, 64
    ret
%endif ; GUARD_LIB_UMATH_BITS_CTZ_ASM
