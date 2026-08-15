%ifndef GUARD_LIB_UMATH_BITS_BITREVERSE_ASM
%define GUARD_LIB_UMATH_BITS_BITREVERSE_ASM
; =============================================================================
; umath - unified math library
; bits/bitreverse.asm - reverse bit order
; =============================================================================
; functions:
;   umath_bitrev8  (u8  -> u8)
;   umath_bitrev16 (u16 -> u16)
;   umath_bitrev32 (u32 -> u32)
;   umath_bitrev64 (u64 -> u64)
;
; args:    rdi = value
; returns: rax = bit-reversed value
;
; algorithm: parallel bit reversal via swap at each power-of-2 granularity
;   step 1 → swap odd/even bits         mask 0x5555...
;   step 2 → swap consecutive pairs     mask 0x3333...
;   step 3 → swap nibbles               mask 0x0F0F...
;   step 4 → bswap (swap bytes)
;   step 5 → swap 16-bit words (64-bit only)
;   step 6 → swap 32-bit halves (64-bit only)
; =============================================================================

bits 64
section .text

; -----------------------------------------------------------------------------
; umath_bitrev8 - reverse bits in 8-bit value
; args:    dil = value (u8)
; returns: al  = bit-reversed u8
; -----------------------------------------------------------------------------
global umath_bitrev8
umath_bitrev8:
    movzx   eax, dil

    ; swap odd/even bits
    mov     ecx, eax
    shr     ecx, 1
    and     ecx, 0x55
    and     eax, 0x55
    shl     eax, 1
    or      eax, ecx

    ; swap consecutive pairs
    mov     ecx, eax
    shr     ecx, 2
    and     ecx, 0x33
    and     eax, 0x33
    shl     eax, 2
    or      eax, ecx

    ; swap nibbles
    mov     ecx, eax
    shr     ecx, 4
    and     ecx, 0x0F
    and     eax, 0x0F
    shl     eax, 4
    or      eax, ecx

    ret

; -----------------------------------------------------------------------------
; umath_bitrev16 - reverse bits in 16-bit value
; args:    di  = value (u16)
; returns: ax  = bit-reversed u16
; -----------------------------------------------------------------------------
global umath_bitrev16
umath_bitrev16:
    movzx   eax, di

    ; swap odd/even bits
    mov     ecx, eax
    shr     ecx, 1
    and     ecx, 0x5555
    and     eax, 0x5555
    shl     eax, 1
    or      eax, ecx

    ; swap consecutive pairs
    mov     ecx, eax
    shr     ecx, 2
    and     ecx, 0x3333
    and     eax, 0x3333
    shl     eax, 2
    or      eax, ecx

    ; swap nibbles
    mov     ecx, eax
    shr     ecx, 4
    and     ecx, 0x0F0F
    and     eax, 0x0F0F
    shl     eax, 4
    or      eax, ecx

    ; swap bytes
    rol     ax, 8

    ret

; -----------------------------------------------------------------------------
; umath_bitrev32 - reverse bits in 32-bit value
; args:    edi = value (u32)
; returns: eax = bit-reversed u32
; -----------------------------------------------------------------------------
global umath_bitrev32
umath_bitrev32:
    mov     eax, edi

    ; swap odd/even bits
    mov     ecx, eax
    shr     ecx, 1
    and     ecx, 0x55555555
    and     eax, 0x55555555
    shl     eax, 1
    or      eax, ecx

    ; swap consecutive pairs
    mov     ecx, eax
    shr     ecx, 2
    and     ecx, 0x33333333
    and     eax, 0x33333333
    shl     eax, 2
    or      eax, ecx

    ; swap nibbles
    mov     ecx, eax
    shr     ecx, 4
    and     ecx, 0x0F0F0F0F
    and     eax, 0x0F0F0F0F
    shl     eax, 4
    or      eax, ecx

    ; swap bytes + swap 16-bit words via bswap
    bswap   eax

    ret

; -----------------------------------------------------------------------------
; umath_bitrev64 - reverse bits in 64-bit value
; args:    rdi = value (u64)
; returns: rax = bit-reversed u64
; -----------------------------------------------------------------------------
global umath_bitrev64
umath_bitrev64:
    mov     rax, rdi

    ; swap odd/even bits
    mov     rcx, rax
    shr     rcx, 1
    mov     rdx, 0x5555555555555555
    and     rcx, rdx
    and     rax, rdx
    shl     rax, 1
    or      rax, rcx

    ; swap consecutive pairs
    mov     rcx, rax
    shr     rcx, 2
    mov     rdx, 0x3333333333333333
    and     rcx, rdx
    and     rax, rdx
    shl     rax, 2
    or      rax, rcx

    ; swap nibbles
    mov     rcx, rax
    shr     rcx, 4
    mov     rdx, 0x0F0F0F0F0F0F0F0F
    and     rcx, rdx
    and     rax, rdx
    shl     rax, 4
    or      rax, rcx

    ; swap bytes + swap 16-bit words + swap 32-bit halves via bswap
    bswap   rax

    ret
%endif ; GUARD_LIB_UMATH_BITS_BITREVERSE_ASM
