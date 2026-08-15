%ifndef GUARD_LIB_UMATH_BITS_BIT128_ASM
%define GUARD_LIB_UMATH_BITS_BIT128_ASM
; =============================================================================
; umath - unified math library
; bits/bit128.asm - 128-bit operations (XMM register width)
; =============================================================================
; used for: INT128/UINT128 arithmetic, FP128 bit access, CF64 (complex FP64),
;           XMM-level SIMD primitives
;
; representation convention for 128-bit integers:
;   passed/returned as two u64 halves: lo (rdi/rax), hi (rsi/rdx)
;   i.e. value = (hi << 64) | lo
;
; functions:
;   --- integer 128-bit (lo,hi pairs) ---
;   umath_bit128_add         (a_lo,a_hi, b_lo,b_hi -> rax=lo, rdx=hi)
;   umath_bit128_sub         (a_lo,a_hi, b_lo,b_hi -> rax=lo, rdx=hi)
;   umath_bit128_and/or/xor/not
;   umath_bit128_shl         (lo,hi, amount -> rax=lo, rdx=hi)
;   umath_bit128_shr         (lo,hi, amount -> rax=lo, rdx=hi)  logical
;   umath_bit128_sar         (lo,hi, amount -> rax=lo, rdx=hi)  arithmetic
;   umath_bit128_cmp_u       (a_lo,a_hi, b_lo,b_hi -> -1/0/1)
;   umath_bit128_cmp_s       (a_lo,a_hi, b_lo,b_hi -> -1/0/1)
;   umath_bit128_bswap       (lo,hi -> rax=new_lo, rdx=new_hi)
;   umath_bit128_popcount    (lo,hi -> total popcount)
;   umath_bit128_clz         (lo,hi -> leading zero count, 0-128)
;   umath_bit128_ctz         (lo,hi -> trailing zero count, 0-128)
;   --- XMM memory ops ---
;   umath_bit128_load        (*ptr -> loads into xmm0, aligned)
;   umath_bit128_store       (*ptr, xmm0 -> stores, aligned)
;   umath_bit128_zero        (-> xmm0 = 0)
;   umath_bit128_all_ones    (-> xmm0 = all 1 bits)
;   --- FP128 ---
;   umath_bit128_fp128_sign       (lo,hi -> sign bit)
;   umath_bit128_fp128_exponent   (lo,hi -> 15-bit exponent)
;   --- CF64 (complex FP64, lo=real bits, hi=imag bits) ---
;   umath_bit128_cf64_real    (lo,hi -> rax = real fp64 bits)
;   umath_bit128_cf64_imag    (lo,hi -> rax = imag fp64 bits)
;   umath_bit128_cf64_compose (re_bits, im_bits -> rax=lo, rdx=hi)
;   umath_bit128_cf64_conjugate (lo,hi -> rax=lo, rdx=hi with imag sign flipped)
; =============================================================================

bits 64
section .text

; =============================================================================
; 128-bit integer arithmetic (lo/hi pair convention)
; =============================================================================

; -----------------------------------------------------------------------------
; umath_bit128_add - 128-bit add
; args: rdi=a_lo, rsi=a_hi, rdx=b_lo, rcx=b_hi
; returns: rax = result_lo, rdx = result_hi
; -----------------------------------------------------------------------------
global umath_bit128_add
umath_bit128_add:
    mov     rax, rdi
    add     rax, rdx            ; lo = a_lo + b_lo
    mov     rdx, rsi
    adc     rdx, rcx            ; hi = a_hi + b_hi + carry
    ret

; -----------------------------------------------------------------------------
; umath_bit128_sub - 128-bit subtract
; args: rdi=a_lo, rsi=a_hi, rdx=b_lo, rcx=b_hi
; returns: rax = result_lo, rdx = result_hi
; -----------------------------------------------------------------------------
global umath_bit128_sub
umath_bit128_sub:
    mov     rax, rdi
    sub     rax, rdx            ; lo = a_lo - b_lo
    mov     r8, rsi
    sbb     r8, rcx             ; hi = a_hi - b_hi - borrow
    mov     rdx, r8
    ret

; -----------------------------------------------------------------------------
; umath_bit128_and / or / xor / not
; args: rdi=a_lo, rsi=a_hi, rdx=b_lo, rcx=b_hi  (not: only a_lo,a_hi used)
; returns: rax = result_lo, rdx = result_hi
; -----------------------------------------------------------------------------
global umath_bit128_and
umath_bit128_and:
    mov     rax, rdi
    and     rax, rdx
    mov     rdx, rsi
    and     rdx, rcx
    ret

global umath_bit128_or
umath_bit128_or:
    mov     rax, rdi
    or      rax, rdx
    mov     rdx, rsi
    or      rdx, rcx
    ret

global umath_bit128_xor
umath_bit128_xor:
    mov     rax, rdi
    xor     rax, rdx
    mov     rdx, rsi
    xor     rdx, rcx
    ret

; -----------------------------------------------------------------------------
; umath_bit128_not - bitwise NOT
; args: rdi=a_lo, rsi=a_hi
; returns: rax = ~a_lo, rdx = ~a_hi
; -----------------------------------------------------------------------------
global umath_bit128_not
umath_bit128_not:
    mov     rax, rdi
    not     rax
    mov     rdx, rsi
    not     rdx
    ret

; -----------------------------------------------------------------------------
; umath_bit128_shl - 128-bit logical shift left
; args: rdi=lo, rsi=hi, edx=amount (0-127, masked to 0-127)
; returns: rax = result_lo, rdx = result_hi
; -----------------------------------------------------------------------------
global umath_bit128_shl
umath_bit128_shl:
    push    rbx
    mov     rax, rdi            ; lo
    mov     rbx, rsi            ; hi
    mov     ecx, edx
    and     ecx, 0x7F           ; amount mod 128
    test    ecx, ecx
    jz      .done
    cmp     ecx, 64
    jge     .shift_ge64
    ; shift < 64: hi = (hi << amount) | (lo >> (64-amount)), lo = lo << amount
    mov     r8, rax             ; save lo
    shl     rbx, cl
    mov     r9, 64
    sub     r9, rcx
    mov     rcx, r9
    shr     r8, cl
    or      rbx, r8
    mov     rcx, edx
    and     ecx, 0x7F
    shl     rax, cl
    jmp     .store
.shift_ge64:
    ; shift >= 64: hi = lo << (amount-64), lo = 0
    mov     r9, ecx
    sub     r9, 64
    mov     rbx, rax
    mov     rcx, r9
    shl     rbx, cl
    xor     rax, rax
.store:
    mov     rdx, rbx
.done:
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; umath_bit128_shr - 128-bit logical shift right
; args: rdi=lo, rsi=hi, edx=amount (0-127)
; returns: rax = result_lo, rdx = result_hi
; -----------------------------------------------------------------------------
global umath_bit128_shr
umath_bit128_shr:
    push    rbx
    mov     rax, rdi            ; lo
    mov     rbx, rsi            ; hi
    mov     ecx, edx
    and     ecx, 0x7F
    test    ecx, ecx
    jz      .done
    cmp     ecx, 64
    jge     .shift_ge64
    ; lo = (lo >> amount) | (hi << (64-amount)), hi = hi >> amount
    mov     r8, rbx             ; save hi
    shr     rax, cl
    mov     r9, 64
    sub     r9, rcx
    mov     rcx, r9
    shl     r8, cl
    or      rax, r8
    mov     rcx, edx
    and     ecx, 0x7F
    shr     rbx, cl
    jmp     .store
.shift_ge64:
    mov     r9, ecx
    sub     r9, 64
    mov     rax, rbx
    mov     rcx, r9
    shr     rax, cl
    xor     rbx, rbx
.store:
    mov     rdx, rbx
.done:
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; umath_bit128_sar - 128-bit arithmetic shift right (sign-extending)
; args: rdi=lo, rsi=hi, edx=amount (0-127)
; returns: rax = result_lo, rdx = result_hi
; -----------------------------------------------------------------------------
global umath_bit128_sar
umath_bit128_sar:
    push    rbx
    mov     rax, rdi
    mov     rbx, rsi
    mov     ecx, edx
    and     ecx, 0x7F
    test    ecx, ecx
    jz      .done
    cmp     ecx, 64
    jge     .shift_ge64
    mov     r8, rbx
    shr     rax, cl
    mov     r9, 64
    sub     r9, rcx
    mov     rcx, r9
    shl     r8, cl
    or      rax, r8
    mov     rcx, edx
    and     ecx, 0x7F
    sar     rbx, cl             ; arithmetic shift preserves sign in hi
    jmp     .store
.shift_ge64:
    mov     r9, ecx
    sub     r9, 64
    mov     rax, rbx
    mov     rcx, r9
    sar     rax, cl             ; sign-extend from hi
    ; hi becomes all sign bits
    sar     rbx, 63             ; rbx = 0 or -1 depending on sign
.store:
    mov     rdx, rbx
.done:
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; umath_bit128_cmp_u - unsigned 128-bit comparison
; args: rdi=a_lo, rsi=a_hi, rdx=b_lo, rcx=b_hi
; returns: eax = -1/0/1
; -----------------------------------------------------------------------------
global umath_bit128_cmp_u
umath_bit128_cmp_u:
    cmp     rsi, rcx
    jne     .hi_differs
    cmp     rdi, rdx
    je      .eq
    jb      .lt
    mov     eax, 1
    ret
.hi_differs:
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
; umath_bit128_cmp_s - signed 128-bit comparison
; args: rdi=a_lo, rsi=a_hi, rdx=b_lo, rcx=b_hi
; returns: eax = -1/0/1
; -----------------------------------------------------------------------------
global umath_bit128_cmp_s
umath_bit128_cmp_s:
    ; compare hi parts as signed first
    cmp     rsi, rcx
    jne     .hi_differs_s
    ; hi equal: compare lo as unsigned
    cmp     rdi, rdx
    je      .eq
    jb      .lt
    mov     eax, 1
    ret
.hi_differs_s:
    jl      .lt                 ; signed less-than on hi
    mov     eax, 1
    ret
.eq:
    xor     eax, eax
    ret
.lt:
    mov     eax, -1
    ret

; -----------------------------------------------------------------------------
; umath_bit128_bswap - byte-swap full 128-bit value
; args: rdi=lo, rsi=hi
; returns: rax = bswap(hi), rdx = bswap(lo)   (note: halves swap positions)
; -----------------------------------------------------------------------------
global umath_bit128_bswap
umath_bit128_bswap:
    mov     rax, rsi
    mov     rdx, rdi
    bswap   rax
    bswap   rdx
    ret

; -----------------------------------------------------------------------------
; umath_bit128_popcount - total population count across 128 bits
; args: rdi=lo, rsi=hi
; returns: eax = popcount (0-128)
; -----------------------------------------------------------------------------
global umath_bit128_popcount
umath_bit128_popcount:
    popcnt  rax, rdi
    popcnt  rdx, rsi
    add     eax, edx
    ret

; -----------------------------------------------------------------------------
; umath_bit128_clz - count leading zeros across 128 bits
; args: rdi=lo, rsi=hi
; returns: eax = clz (0-128)
; -----------------------------------------------------------------------------
global umath_bit128_clz
umath_bit128_clz:
    test    rsi, rsi
    jz      .hi_zero
    lzcnt   rax, rsi
    ret
.hi_zero:
    lzcnt   rax, rdi
    add     eax, 64
    ret

; -----------------------------------------------------------------------------
; umath_bit128_ctz - count trailing zeros across 128 bits
; args: rdi=lo, rsi=hi
; returns: eax = ctz (0-128)
; -----------------------------------------------------------------------------
global umath_bit128_ctz
umath_bit128_ctz:
    test    rdi, rdi
    jz      .lo_zero
    tzcnt   rax, rdi
    ret
.lo_zero:
    tzcnt   rax, rsi
    add     eax, 64
    ret

; =============================================================================
; XMM memory operations
; =============================================================================

; -----------------------------------------------------------------------------
; umath_bit128_load - load 128 bits from aligned memory into xmm0
; args: rdi = pointer (must be 16-byte aligned)
; returns: xmm0 = loaded value
; -----------------------------------------------------------------------------
global umath_bit128_load
umath_bit128_load:
    movdqa  xmm0, [rdi]
    ret

; -----------------------------------------------------------------------------
; umath_bit128_store - store xmm0 to aligned memory
; args: rdi = pointer (must be 16-byte aligned), xmm0 = value to store
; -----------------------------------------------------------------------------
global umath_bit128_store
umath_bit128_store:
    movdqa  [rdi], xmm0
    ret

; -----------------------------------------------------------------------------
; umath_bit128_zero - return xmm0 = all zeros
; -----------------------------------------------------------------------------
global umath_bit128_zero
umath_bit128_zero:
    pxor    xmm0, xmm0
    ret

; -----------------------------------------------------------------------------
; umath_bit128_all_ones - return xmm0 = all 1 bits
; -----------------------------------------------------------------------------
global umath_bit128_all_ones
umath_bit128_all_ones:
    pcmpeqd xmm0, xmm0
    ret

; =============================================================================
; FP128 bit field operations
; layout: [127]=sign [126:112]=exponent(15) [111:0]=mantissa(112)
; lo = bits[63:0], hi = bits[127:64]
; =============================================================================

; -----------------------------------------------------------------------------
; umath_bit128_fp128_sign - extract sign bit
; args: rdi=lo, rsi=hi
; returns: eax = sign bit (0/1) — sign is bit 127, i.e. bit 63 of hi
; -----------------------------------------------------------------------------
global umath_bit128_fp128_sign
umath_bit128_fp128_sign:
    mov     rax, rsi
    shr     rax, 63
    and     eax, 1
    ret

; -----------------------------------------------------------------------------
; umath_bit128_fp128_exponent - extract 15-bit exponent
; args: rdi=lo, rsi=hi
; returns: eax = exponent (0-32767) — bits [126:112], i.e. bits[62:48] of hi
; -----------------------------------------------------------------------------
global umath_bit128_fp128_exponent
umath_bit128_fp128_exponent:
    mov     rax, rsi
    shr     rax, 48
    and     eax, 0x7FFF
    ret

; =============================================================================
; CF64 operations - complex FP64 as 128-bit (lo=real fp64, hi=imag fp64)
; =============================================================================

; -----------------------------------------------------------------------------
; umath_bit128_cf64_real - extract real part (fp64 bits)
; args: rdi=lo, rsi=hi
; returns: rax = real part fp64 bits (= lo)
; -----------------------------------------------------------------------------
global umath_bit128_cf64_real
umath_bit128_cf64_real:
    mov     rax, rdi
    ret

; -----------------------------------------------------------------------------
; umath_bit128_cf64_imag - extract imaginary part (fp64 bits)
; args: rdi=lo, rsi=hi
; returns: rax = imaginary part fp64 bits (= hi)
; -----------------------------------------------------------------------------
global umath_bit128_cf64_imag
umath_bit128_cf64_imag:
    mov     rax, rsi
    ret

; -----------------------------------------------------------------------------
; umath_bit128_cf64_compose - pack real and imaginary fp64 bits
; args: rdi = real part bits, rsi = imaginary part bits
; returns: rax = lo (=real), rdx = hi (=imag)
; -----------------------------------------------------------------------------
global umath_bit128_cf64_compose
umath_bit128_cf64_compose:
    mov     rax, rdi
    mov     rdx, rsi
    ret

; -----------------------------------------------------------------------------
; umath_bit128_cf64_conjugate - flip sign of imaginary part
; args: rdi=lo (real), rsi=hi (imag)
; returns: rax = lo (unchanged real), rdx = hi (imag with sign flipped)
; -----------------------------------------------------------------------------
global umath_bit128_cf64_conjugate
umath_bit128_cf64_conjugate:
    mov     rax, rdi
    mov     rdx, rsi
    mov     rcx, 0x8000000000000000
    xor     rdx, rcx
    ret
%endif ; GUARD_LIB_UMATH_BITS_BIT128_ASM
