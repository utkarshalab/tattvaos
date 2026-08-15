%ifndef GUARD_LIB_UMATH_BITS_POPCOUNT_ASM
%define GUARD_LIB_UMATH_BITS_POPCOUNT_ASM
; =============================================================================
; umath - unified math library
; bits/popcount.asm - population count (count set bits)
; =============================================================================
; functions:
;   umath_popcount8  (u8  -> u8)
;   umath_popcount16 (u16 -> u16)
;   umath_popcount32 (u32 -> u32)
;   umath_popcount64 (u64 -> u64)
;
; args:    rdi = value
; returns: rax = number of set bits
; =============================================================================

bits 64
section .text

; -----------------------------------------------------------------------------
; umath_popcount8 - count set bits in 8-bit value
; args:    dil = value (u8)
; returns: al  = popcount result (0-8)
; -----------------------------------------------------------------------------
global umath_popcount8
umath_popcount8:
    movzx   edi, dil
    popcnt  eax, edi
    ret

; -----------------------------------------------------------------------------
; umath_popcount16 - count set bits in 16-bit value
; args:    di  = value (u16)
; returns: ax  = popcount result (0-16)
; -----------------------------------------------------------------------------
global umath_popcount16
umath_popcount16:
    movzx   edi, di
    popcnt  eax, edi
    ret

; -----------------------------------------------------------------------------
; umath_popcount32 - count set bits in 32-bit value
; args:    edi = value (u32)
; returns: eax = popcount result (0-32)
; -----------------------------------------------------------------------------
global umath_popcount32
umath_popcount32:
    popcnt  eax, edi
    ret

; -----------------------------------------------------------------------------
; umath_popcount64 - count set bits in 64-bit value
; args:    rdi = value (u64)
; returns: rax = popcount result (0-64)
; -----------------------------------------------------------------------------
global umath_popcount64
umath_popcount64:
    popcnt  rax, rdi
    ret

; -----------------------------------------------------------------------------
; umath_popcount32_soft - software fallback (no POPCNT instruction)
; args:    edi = value (u32)
; returns: eax = popcount result (0-32)
; note:    Hamming weight via parallel bit summation
;          use only when POPCNT unavailable
; -----------------------------------------------------------------------------
global umath_popcount32_soft
umath_popcount32_soft:
    mov     eax, edi
    mov     ecx, eax
    shr     ecx, 1
    and     ecx, 0x55555555         ; ecx = (x >> 1) & 0x55555555
    sub     eax, ecx                ; eax = x - ((x >> 1) & 0x55555555)
    mov     ecx, eax
    shr     eax, 2
    and     ecx, 0x33333333
    and     eax, 0x33333333
    add     eax, ecx                ; eax = pair sums
    mov     ecx, eax
    shr     ecx, 4
    add     eax, ecx
    and     eax, 0x0F0F0F0F         ; eax = nibble sums
    imul    eax, eax, 0x01010101    ; sum all bytes into top byte
    shr     eax, 24                 ; extract top byte
    ret

; -----------------------------------------------------------------------------
; umath_popcount64_soft - software fallback (no POPCNT instruction)
; args:    rdi = value (u64)
; returns: rax = popcount result (0-64)
; note:    Hamming weight via parallel bit summation
;          use only when POPCNT unavailable
; -----------------------------------------------------------------------------
global umath_popcount64_soft
umath_popcount64_soft:
    mov     rax, rdi
    mov     rcx, rax
    shr     rcx, 1
    mov     rdx, 0x5555555555555555
    and     rcx, rdx
    sub     rax, rcx
    mov     rcx, rax
    shr     rax, 2
    mov     rdx, 0x3333333333333333
    and     rcx, rdx
    and     rax, rdx
    add     rax, rcx
    mov     rcx, rax
    shr     rcx, 4
    add     rax, rcx
    mov     rdx, 0x0F0F0F0F0F0F0F0F
    and     rax, rdx
    mov     rdx, 0x0101010101010101
    imul    rax, rdx
    shr     rax, 56
    ret

; -----------------------------------------------------------------------------
; umath_popcount_buf - popcount over a buffer of u64 values
; args:    rdi = pointer to u64 buffer
;          rsi = count (number of u64 elements)
; returns: rax = total popcount across buffer
; -----------------------------------------------------------------------------
global umath_popcount_buf
umath_popcount_buf:
    xor     rax, rax
    test    rsi, rsi
    jz      .done
.loop:
    popcnt  rcx, qword [rdi]
    add     rax, rcx
    add     rdi, 8
    dec     rsi
    jnz     .loop
.done:
    ret
%endif ; GUARD_LIB_UMATH_BITS_POPCOUNT_ASM
