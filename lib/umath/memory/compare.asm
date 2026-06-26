; =============================================================================
; umath - unified math library
; memory/compare.asm - highly optimized memory comparison (memcmp)
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; Performance Optimizations:
;   - Loop unrolling (4x) in SSE and AVX2 pathways to compare 64 bytes and 128
;     bytes per iteration respectively.
;   - Mismatch scanning: utilizes hardware tzcnt and mask extraction (pmovmskb,
;     vpmovmskb) to quickly find the exact mismatch index on loop break.
;   - Lexicographical return compatibility: returns -1 (a < b), 0 (a == b), 1 (a > b).
; =============================================================================

bits 64
section .text

; -----------------------------------------------------------------------------
; umath_memcmp - standard baseline memory comparison (using repe cmpsb)
; args:    rdi = pointer to block a
;          rsi = pointer to block b
;          rdx = size in bytes
; returns: rax = -1 (a < b), 0 (a == b), 1 (a > b)
; -----------------------------------------------------------------------------
global umath_memcmp
umath_memcmp:
    xor     rax, rax            ; clear return value
    test    rdx, rdx
    jz      .done

    mov     rcx, rdx
    repe    cmpsb
    je      .equal
    jc      .less               ; CF=1 -> a < b

    mov     rax, 1              ; a > b
    ret
.less:
    mov     rax, -1             ; a < b
    ret
.equal:
    xor     rax, rax
.done:
    ret

; -----------------------------------------------------------------------------
; umath_memcmp_sse - compare using unrolled SSE 16-byte blocks
; args:    rdi = pointer to block a
;          rsi = pointer to block b
;          rdx = size in bytes
; returns: rax = -1 (a < b), 0 (a == b), 1 (a > b)
; -----------------------------------------------------------------------------
global umath_memcmp_sse
umath_memcmp_sse:
    xor     rax, rax
    test    rdx, rdx
    jz      .done

    cmp     rdx, 16
    jb      .residuals

    ; check if we can run unrolled loop (>= 64 bytes)
    cmp     rdx, 64
    jb      .loop16_single

    mov     rcx, rdx
    shr     rcx, 6              ; count of 64-byte blocks (4x 16-byte blocks)

.loop16_unrolled:
    ; load 4 blocks from a and b
    movups  xmm0, [rdi]
    movups  xmm1, [rsi]
    movups  xmm2, [rdi + 16]
    movups  xmm3, [rsi + 16]
    pcmpeqb xmm0, xmm1
    pcmpeqb xmm2, xmm3

    pmovmskb eax, xmm0
    pmovmskb r8d, xmm2
    cmp     eax, 0xFFFF
    jne     .mismatch_unrolled_0
    cmp     r8d, 0xFFFF
    jne     .mismatch_unrolled_1

    movups  xmm4, [rdi + 32]
    movups  xmm5, [rsi + 32]
    movups  xmm6, [rdi + 48]
    movups  xmm7, [rsi + 48]
    pcmpeqb xmm4, xmm5
    pcmpeqb xmm6, xmm7

    pmovmskb eax, xmm4
    pmovmskb r8d, xmm6
    cmp     eax, 0xFFFF
    jne     .mismatch_unrolled_2
    cmp     r8d, 0xFFFF
    jne     .mismatch_unrolled_3

    add     rdi, 64
    add     rsi, 64
    dec     rcx
    jnz     .loop16_unrolled

    and     rdx, 63
    cmp     rdx, 16
    jb      .residuals

.loop16_single:
    mov     rcx, rdx
    shr     rcx, 4

.loop16_single_run:
    movups  xmm0, [rdi]
    movups  xmm1, [rsi]
    pcmpeqb xmm0, xmm1
    pmovmskb eax, xmm0
    cmp     eax, 0xFFFF
    jne     .mismatch16

    add     rdi, 16
    add     rsi, 16
    dec     rcx
    jnz     .loop16_single_run

    and     rdx, 15
.residuals:
    test    rdx, rdx
    jz      .equal_sse
    mov     rcx, rdx
    repe    cmpsb
    je      .equal_sse
    jc      .less_sse
    mov     rax, 1
    ret
.less_sse:
    mov     rax, -1
    ret
.equal_sse:
    xor     rax, rax
    ret

; Mismatch Handlers for unrolled paths
.mismatch_unrolled_0:
    jmp     .mismatch16
.mismatch_unrolled_1:
    add     rdi, 16
    add     rsi, 16
    mov     eax, r8d
    jmp     .mismatch16
.mismatch_unrolled_2:
    add     rdi, 32
    add     rsi, 32
    jmp     .mismatch16
.mismatch_unrolled_3:
    add     rdi, 48
    add     rsi, 48
    mov     eax, r8d
    ; fallthrough to mismatch16

.mismatch16:
    not     eax
    and     eax, 0xFFFF
    tzcnt   eax, eax
    
    movzx   ecx, byte [rdi + rax]
    movzx   edx, byte [rsi + rax]
    cmp     ecx, edx
    jg      .greater_mis
    mov     rax, -1
    ret
.greater_mis:
    mov     rax, 1
.done:
    ret

; -----------------------------------------------------------------------------
; umath_memcmp_avx2 - compare using unrolled AVX2 32-byte blocks
; args:    rdi = pointer to block a
;          rsi = pointer to block b
;          rdx = size in bytes
; returns: rax = -1 (a < b), 0 (a == b), 1 (a > b)
; -----------------------------------------------------------------------------
global umath_memcmp_avx2
umath_memcmp_avx2:
    xor     rax, rax
    test    rdx, rdx
    jz      .done

    cmp     rdx, 32
    jb      .sse_fallback

    ; check if we can run unrolled loop (>= 128 bytes)
    cmp     rdx, 128
    jb      .loop32_single

    mov     rcx, rdx
    shr     rcx, 7              ; count of 128-byte blocks

.loop32_unrolled:
    vmovdqu ymm0, [rdi]
    vmovdqu ymm1, [rsi]
    vmovdqu ymm2, [rdi + 32]
    vmovdqu ymm3, [rsi + 32]
    vpcmpeqb ymm0, ymm0, ymm1
    vpcmpeqb ymm2, ymm2, ymm3

    vpmovmskb eax, ymm0
    vpmovmskb r8d, ymm2
    cmp     eax, 0xFFFFFFFF
    jne     .mismatch32_unrolled_0
    cmp     r8d, 0xFFFFFFFF
    jne     .mismatch32_unrolled_1

    vmovdqu ymm4, [rdi + 64]
    vmovdqu ymm5, [rsi + 64]
    vmovdqu ymm6, [rdi + 96]
    vmovdqu ymm7, [rsi + 96]
    vpcmpeqb ymm4, ymm4, ymm5
    vpcmpeqb ymm6, ymm6, ymm7

    vpmovmskb eax, ymm4
    vpmovmskb r8d, ymm6
    cmp     eax, 0xFFFFFFFF
    jne     .mismatch32_unrolled_2
    cmp     r8d, 0xFFFFFFFF
    jne     .mismatch32_unrolled_3

    add     rdi, 128
    add     rsi, 128
    dec     rcx
    jnz     .loop32_unrolled

    and     rdx, 127
    cmp     rdx, 32
    jb      .sse_fallback

.loop32_single:
    mov     rcx, rdx
    shr     rcx, 5              ; count of remaining 32-byte blocks

.loop32_single_run:
    vmovdqu ymm0, [rdi]
    vmovdqu ymm1, [rsi]
    vpcmpeqb ymm2, ymm0, ymm1
    vpmovmskb eax, ymm2
    cmp     eax, 0xFFFFFFFF
    jne     .mismatch32

    add     rdi, 32
    add     rsi, 32
    dec     rcx
    jnz     .loop32_single_run

    and     rdx, 31
.sse_fallback:
    cmp     rdx, 16
    jb      .residuals
    
    movups  xmm0, [rdi]
    movups  xmm1, [rsi]
    pcmpeqb xmm0, xmm1
    pmovmskb eax, xmm0
    cmp     eax, 0xFFFF
    jne     .mismatch16

    add     rdi, 16
    add     rsi, 16
    sub     rdx, 16

.residuals:
    test    rdx, rdx
    jz      .equal_avx
    mov     rcx, rdx
    repe    cmpsb
    je      .equal_avx
    jc      .less_avx
    mov     rax, 1
    jmp     .done_avx
.less_avx:
    mov     rax, -1
    jmp     .done_avx
.equal_avx:
    xor     rax, rax
    jmp     .done_avx

; Mismatch Handlers for unrolled AVX2 paths
.mismatch32_unrolled_0:
    jmp     .mismatch32
.mismatch32_unrolled_1:
    add     rdi, 32
    add     rsi, 32
    mov     eax, r8d
    jmp     .mismatch32
.mismatch32_unrolled_2:
    add     rdi, 64
    add     rsi, 64
    jmp     .mismatch32
.mismatch32_unrolled_3:
    add     rdi, 96
    add     rsi, 96
    mov     eax, r8d
    ; fallthrough to mismatch32

.mismatch32:
    not     eax
    tzcnt   eax, eax
    
    movzx   ecx, byte [rdi + rax]
    movzx   edx, byte [rsi + rax]
    cmp     ecx, edx
    jg      .greater_mis32
    mov     rax, -1
    jmp     .done_avx
.greater_mis32:
    mov     rax, 1
    jmp     .done_avx

.mismatch16:
    not     eax
    and     eax, 0xFFFF
    tzcnt   eax, eax
    movzx   ecx, byte [rdi + rax]
    movzx   edx, byte [rsi + rax]
    cmp     ecx, edx
    jg      .greater_mis16
    mov     rax, -1
    jmp     .done_avx
.greater_mis16:
    mov     rax, 1

.done_avx:
    vzeroupper
.done:
    ret
