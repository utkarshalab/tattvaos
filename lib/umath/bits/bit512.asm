; =============================================================================
; umath - unified math library
; bits/bit512.asm - 512-bit operations (ZMM register width)
; =============================================================================
; used for: UINT512 (bignum limbs), AVX-512 register-level primitives
;
; representation convention for 512-bit integers:
;   pointer-based; memory layout = 8x u64 words, word[0]=lo .. word[7]=hi
;
; functions:
;   --- integer 512-bit (pointer-based, *u64[8]) ---
;   umath_bit512_add         (*dst, *a, *b -> eax=carry)
;   umath_bit512_sub         (*dst, *a, *b -> eax=borrow)
;   umath_bit512_and/or/xor/not  (*dst, *a, *b -> void)
;   umath_bit512_shl         (*dst, *a, amount -> void, 0-511)
;   umath_bit512_shr         (*dst, *a, amount -> void, 0-511)
;   umath_bit512_cmp_u       (*a, *b -> -1/0/1)
;   umath_bit512_is_zero     (*a -> bool)
;   umath_bit512_popcount    (*a -> count, 0-512)
;   umath_bit512_clz         (*a -> count, 0-512)
;   umath_bit512_ctz         (*a -> count, 0-512)
;   umath_bit512_bswap       (*dst, *a -> void)
;   --- ZMM memory ops (AVX-512) ---
;   umath_bit512_load        (*ptr -> loads into zmm0, aligned 64)
;   umath_bit512_store       (*ptr, zmm0 -> stores, aligned 64)
;   umath_bit512_zero        (-> zmm0 = 0)
;   umath_bit512_all_ones    (-> zmm0 = all 1 bits)
; =============================================================================

bits 64
section .text

; -----------------------------------------------------------------------------
; umath_bit512_add - dst = a + b
; args: rdi=*dst, rsi=*a, rdx=*b  (each points to 8x u64, 64 bytes)
; returns: eax = carry out (0 or 1)
; -----------------------------------------------------------------------------
global umath_bit512_add
umath_bit512_add:
    mov     rax, [rsi]
    add     rax, [rdx]
    mov     [rdi], rax

    mov     rax, [rsi+8]
    adc     rax, [rdx+8]
    mov     [rdi+8], rax

    mov     rax, [rsi+16]
    adc     rax, [rdx+16]
    mov     [rdi+16], rax

    mov     rax, [rsi+24]
    adc     rax, [rdx+24]
    mov     [rdi+24], rax

    mov     rax, [rsi+32]
    adc     rax, [rdx+32]
    mov     [rdi+32], rax

    mov     rax, [rsi+40]
    adc     rax, [rdx+40]
    mov     [rdi+40], rax

    mov     rax, [rsi+48]
    adc     rax, [rdx+48]
    mov     [rdi+48], rax

    mov     rax, [rsi+56]
    adc     rax, [rdx+56]
    mov     [rdi+56], rax

    setc    al
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_bit512_sub - dst = a - b
; args: rdi=*dst, rsi=*a, rdx=*b
; returns: eax = borrow out (0 or 1)
; -----------------------------------------------------------------------------
global umath_bit512_sub
umath_bit512_sub:
    mov     rax, [rsi]
    sub     rax, [rdx]
    mov     [rdi], rax

    mov     rax, [rsi+8]
    sbb     rax, [rdx+8]
    mov     [rdi+8], rax

    mov     rax, [rsi+16]
    sbb     rax, [rdx+16]
    mov     [rdi+16], rax

    mov     rax, [rsi+24]
    sbb     rax, [rdx+24]
    mov     [rdi+24], rax

    mov     rax, [rsi+32]
    sbb     rax, [rdx+32]
    mov     [rdi+32], rax

    mov     rax, [rsi+40]
    sbb     rax, [rdx+40]
    mov     [rdi+40], rax

    mov     rax, [rsi+48]
    sbb     rax, [rdx+48]
    mov     [rdi+48], rax

    mov     rax, [rsi+56]
    sbb     rax, [rdx+56]
    mov     [rdi+56], rax

    setc    al
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_bit512_and - dst = a & b  (two YMM halves)
; args: rdi=*dst, rsi=*a, rdx=*b
; -----------------------------------------------------------------------------
global umath_bit512_and
umath_bit512_and:
    vmovdqu ymm0, [rsi]
    vmovdqu ymm1, [rdx]
    vpand   ymm0, ymm0, ymm1
    vmovdqu [rdi], ymm0
    vmovdqu ymm0, [rsi+32]
    vmovdqu ymm1, [rdx+32]
    vpand   ymm0, ymm0, ymm1
    vmovdqu [rdi+32], ymm0
    ret

; -----------------------------------------------------------------------------
; umath_bit512_or - dst = a | b
; -----------------------------------------------------------------------------
global umath_bit512_or
umath_bit512_or:
    vmovdqu ymm0, [rsi]
    vmovdqu ymm1, [rdx]
    vpor    ymm0, ymm0, ymm1
    vmovdqu [rdi], ymm0
    vmovdqu ymm0, [rsi+32]
    vmovdqu ymm1, [rdx+32]
    vpor    ymm0, ymm0, ymm1
    vmovdqu [rdi+32], ymm0
    ret

; -----------------------------------------------------------------------------
; umath_bit512_xor - dst = a ^ b
; -----------------------------------------------------------------------------
global umath_bit512_xor
umath_bit512_xor:
    vmovdqu ymm0, [rsi]
    vmovdqu ymm1, [rdx]
    vpxor   ymm0, ymm0, ymm1
    vmovdqu [rdi], ymm0
    vmovdqu ymm0, [rsi+32]
    vmovdqu ymm1, [rdx+32]
    vpxor   ymm0, ymm0, ymm1
    vmovdqu [rdi+32], ymm0
    ret

; -----------------------------------------------------------------------------
; umath_bit512_not - dst = ~a
; args: rdi=*dst, rsi=*a
; -----------------------------------------------------------------------------
global umath_bit512_not
umath_bit512_not:
    vpcmpeqd ymm2, ymm2, ymm2    ; all ones
    vmovdqu ymm0, [rsi]
    vpxor   ymm0, ymm0, ymm2
    vmovdqu [rdi], ymm0
    vmovdqu ymm0, [rsi+32]
    vpxor   ymm0, ymm0, ymm2
    vmovdqu [rdi+32], ymm0
    ret

; -----------------------------------------------------------------------------
; umath_bit512_shl - 512-bit logical shift left
; args: rdi=*dst, rsi=*a, edx=amount (0-511)
; algorithm: word-shift (multiples of 64) then bit-shift with carry chain,
;            high word to low word, using a local stack copy of source
; -----------------------------------------------------------------------------
global umath_bit512_shl
umath_bit512_shl:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 64

    mov     rax, [rsi]
    mov     [rsp], rax
    mov     rax, [rsi+8]
    mov     [rsp+8], rax
    mov     rax, [rsi+16]
    mov     [rsp+16], rax
    mov     rax, [rsi+24]
    mov     [rsp+24], rax
    mov     rax, [rsi+32]
    mov     [rsp+32], rax
    mov     rax, [rsi+40]
    mov     [rsp+40], rax
    mov     rax, [rsi+48]
    mov     [rsp+48], rax
    mov     rax, [rsi+56]
    mov     [rsp+56], rax

    mov     ecx, edx
    and     ecx, 0x1FF          ; mod 512
    mov     ebx, ecx
    shr     ebx, 6              ; word shift (0-7)
    and     ecx, 63             ; bit shift (0-63)

    ; word shift: dst_word[i] = src_word[i - word_shift] (or 0)
    xor     r12d, r12d
.word_shift_loop:
    cmp     r12d, 8
    jge     .bitshift
    mov     r13d, r12d
    sub     r13d, ebx
    cmp     r13d, 0
    jl      .zero_word
    mov     rax, [rsp + r13*8]
    jmp     .store_word
.zero_word:
    xor     rax, rax
.store_word:
    mov     [rdi + r12*8], rax
    inc     r12d
    jmp     .word_shift_loop

.bitshift:
    test    ecx, ecx
    jz      .done
    mov     r8, 64
    sub     r8, rcx
    mov     r14, 7
.bit_loop:
    cmp     r14, 0
    jl      .done
    mov     rax, [rdi + r14*8]
    cmp     r14, 0
    je      .top_only
    mov     r15, [rdi + r14*8 - 8]
    mov     r9, r15
    shr     r9, r8b
    shl     rax, cl
    or      rax, r9
    mov     [rdi + r14*8], rax
    dec     r14
    jmp     .bit_loop
.top_only:
    shl     rax, cl
    mov     [rdi + r14*8], rax
    dec     r14
    jmp     .bit_loop

.done:
    add     rsp, 64
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; umath_bit512_shr - 512-bit logical shift right
; args: rdi=*dst, rsi=*a, edx=amount (0-511)
; -----------------------------------------------------------------------------
global umath_bit512_shr
umath_bit512_shr:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 64

    mov     rax, [rsi]
    mov     [rsp], rax
    mov     rax, [rsi+8]
    mov     [rsp+8], rax
    mov     rax, [rsi+16]
    mov     [rsp+16], rax
    mov     rax, [rsi+24]
    mov     [rsp+24], rax
    mov     rax, [rsi+32]
    mov     [rsp+32], rax
    mov     rax, [rsi+40]
    mov     [rsp+40], rax
    mov     rax, [rsi+48]
    mov     [rsp+48], rax
    mov     rax, [rsi+56]
    mov     [rsp+56], rax

    mov     ecx, edx
    and     ecx, 0x1FF
    mov     ebx, ecx
    shr     ebx, 6
    and     ecx, 63

    xor     r12d, r12d
.word_shift_loop:
    cmp     r12d, 8
    jge     .bitshift
    mov     r13d, r12d
    add     r13d, ebx
    cmp     r13d, 8
    jge     .zero_word
    mov     rax, [rsp + r13*8]
    jmp     .store_word
.zero_word:
    xor     rax, rax
.store_word:
    mov     [rdi + r12*8], rax
    inc     r12d
    jmp     .word_shift_loop

.bitshift:
    test    ecx, ecx
    jz      .done
    mov     r8, 64
    sub     r8, rcx
    xor     r14, r14
.bit_loop:
    cmp     r14, 8
    jge     .done
    mov     rax, [rdi + r14*8]
    cmp     r14, 7
    je      .top_only
    mov     r15, [rdi + r14*8 + 8]
    mov     r9, r15
    shl     r9, r8b
    shr     rax, cl
    or      rax, r9
    mov     [rdi + r14*8], rax
    inc     r14
    jmp     .bit_loop
.top_only:
    shr     rax, cl
    mov     [rdi + r14*8], rax
    inc     r14
    jmp     .bit_loop

.done:
    add     rsp, 64
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; umath_bit512_cmp_u - unsigned 512-bit comparison (word7 = most significant)
; args: rdi=*a, rsi=*b
; returns: eax = -1/0/1
; -----------------------------------------------------------------------------
global umath_bit512_cmp_u
umath_bit512_cmp_u:
    mov     ecx, 7
.loop:
    mov     rax, [rdi + rcx*8]
    cmp     rax, [rsi + rcx*8]
    jne     .differ
    dec     ecx
    cmp     ecx, 0
    jge     .loop
    xor     eax, eax
    ret
.differ:
    jb      .lt
    mov     eax, 1
    ret
.lt:
    mov     eax, -1
    ret

; -----------------------------------------------------------------------------
; umath_bit512_is_zero - check if all 512 bits are zero
; args: rdi=*a
; returns: eax = 1 if zero, 0 otherwise
; -----------------------------------------------------------------------------
global umath_bit512_is_zero
umath_bit512_is_zero:
    mov     rax, [rdi]
    or      rax, [rdi+8]
    or      rax, [rdi+16]
    or      rax, [rdi+24]
    or      rax, [rdi+32]
    or      rax, [rdi+40]
    or      rax, [rdi+48]
    or      rax, [rdi+56]
    test    rax, rax
    setz    al
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_bit512_popcount - total population count
; args: rdi=*a
; returns: eax = popcount (0-512)
; -----------------------------------------------------------------------------
global umath_bit512_popcount
umath_bit512_popcount:
    xor     eax, eax
    popcnt  rcx, qword [rdi]
    add     rax, rcx
    popcnt  rcx, qword [rdi+8]
    add     rax, rcx
    popcnt  rcx, qword [rdi+16]
    add     rax, rcx
    popcnt  rcx, qword [rdi+24]
    add     rax, rcx
    popcnt  rcx, qword [rdi+32]
    add     rax, rcx
    popcnt  rcx, qword [rdi+40]
    add     rax, rcx
    popcnt  rcx, qword [rdi+48]
    add     rax, rcx
    popcnt  rcx, qword [rdi+56]
    add     rax, rcx
    ret

; -----------------------------------------------------------------------------
; umath_bit512_clz - leading zero count (word7 = most significant)
; args: rdi=*a
; returns: eax = clz (0-512)
; -----------------------------------------------------------------------------
global umath_bit512_clz
umath_bit512_clz:
    mov     ecx, 7
.loop:
    mov     rax, [rdi + rcx*8]
    test    rax, rax
    jnz     .found
    dec     ecx
    cmp     ecx, 0
    jge     .loop
    mov     eax, 512
    ret
.found:
    lzcnt   rax, rax
    mov     edx, 7
    sub     edx, ecx
    imul    edx, 64
    add     eax, edx
    ret

; -----------------------------------------------------------------------------
; umath_bit512_ctz - trailing zero count (word0 = least significant)
; args: rdi=*a
; returns: eax = ctz (0-512)
; -----------------------------------------------------------------------------
global umath_bit512_ctz
umath_bit512_ctz:
    xor     ecx, ecx
.loop:
    mov     rax, [rdi + rcx*8]
    test    rax, rax
    jnz     .found
    inc     ecx
    cmp     ecx, 8
    jl      .loop
    mov     eax, 512
    ret
.found:
    tzcnt   rax, rax
    mov     edx, ecx
    imul    edx, 64
    add     eax, edx
    ret

; -----------------------------------------------------------------------------
; umath_bit512_bswap - byte-swap each word and reverse word order
; args: rdi=*dst, rsi=*a
; -----------------------------------------------------------------------------
global umath_bit512_bswap
umath_bit512_bswap:
    mov     rax, [rsi]
    bswap   rax
    mov     [rdi+56], rax

    mov     rax, [rsi+8]
    bswap   rax
    mov     [rdi+48], rax

    mov     rax, [rsi+16]
    bswap   rax
    mov     [rdi+40], rax

    mov     rax, [rsi+24]
    bswap   rax
    mov     [rdi+32], rax

    mov     rax, [rsi+32]
    bswap   rax
    mov     [rdi+24], rax

    mov     rax, [rsi+40]
    bswap   rax
    mov     [rdi+16], rax

    mov     rax, [rsi+48]
    bswap   rax
    mov     [rdi+8], rax

    mov     rax, [rsi+56]
    bswap   rax
    mov     [rdi], rax
    ret

; =============================================================================
; ZMM memory operations (AVX-512)
; =============================================================================

; -----------------------------------------------------------------------------
; umath_bit512_load - load 512 bits from aligned memory into zmm0
; args: rdi = pointer (must be 64-byte aligned)
; returns: zmm0 = loaded value
; note: requires AVX-512F
; -----------------------------------------------------------------------------
global umath_bit512_load
umath_bit512_load:
    vmovdqa64 zmm0, [rdi]
    ret

; -----------------------------------------------------------------------------
; umath_bit512_store - store zmm0 to aligned memory
; args: rdi = pointer (must be 64-byte aligned), zmm0 = value
; -----------------------------------------------------------------------------
global umath_bit512_store
umath_bit512_store:
    vmovdqa64 [rdi], zmm0
    ret

; -----------------------------------------------------------------------------
; umath_bit512_zero - return zmm0 = all zeros
; -----------------------------------------------------------------------------
global umath_bit512_zero
umath_bit512_zero:
    vpxorq  zmm0, zmm0, zmm0
    ret

; -----------------------------------------------------------------------------
; umath_bit512_all_ones - return zmm0 = all 1 bits
; -----------------------------------------------------------------------------
global umath_bit512_all_ones
umath_bit512_all_ones:
    vpternlogd zmm0, zmm0, zmm0, 0xFF
    ret