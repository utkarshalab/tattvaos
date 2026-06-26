; =============================================================================
; umath - unified math library
; memory/move.asm - highly optimized overlap-safe memory move (memmove)
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; Performance Optimizations:
;   - Loop unrolling (4x) in both forward and backward copy pathways to maximize
;     superscalar execution and minimize loop overhead.
;   - Precise overlapping detection: copies backward if and only if
;     (dst > src) AND (dst < src + size).
; =============================================================================

bits 64
section .text

; -----------------------------------------------------------------------------
; umath_memmove - standard baseline overlap-safe memory move (using rep movsb)
; args:    rdi = destination address
;          rsi = source address
;          rdx = count in bytes
; returns: rax = destination address
; -----------------------------------------------------------------------------
global umath_memmove
umath_memmove:
    mov     rax, rdi
    test    rdx, rdx
    jz      .done
    cmp     rdi, rsi
    je      .done               ; dst == src -> no-op

    ; check overlap: dst > src AND dst < src + size
    mov     rcx, rsi
    add     rcx, rdx            ; rcx = src + size
    cmp     rdi, rsi
    jbe     .forward            ; dst < src -> forward copy is safe
    cmp     rdi, rcx
    jae     .forward            ; dst >= src + size -> forward copy is safe

    ; backward copy: rep movsb with DF = 1
    std                         ; set direction flag (backward)
    lea     rsi, [rsi + rdx - 1]
    lea     rdi, [rdi + rdx - 1]
    mov     rcx, rdx
    rep     movsb
    cld                         ; ALWAYS restore clean direction flag!
    ret

.forward:
    cld
    mov     rcx, rdx
    rep     movsb
.done:
    ret

; -----------------------------------------------------------------------------
; umath_memmove_sse - overlap-safe memory move using 16-byte SSE blocks
; args:    rdi = destination address
;          rsi = source address
;          rdx = count in bytes
; returns: rax = destination address
; -----------------------------------------------------------------------------
global umath_memmove_sse
umath_memmove_sse:
    mov     rax, rdi
    test    rdx, rdx
    jz      .done
    cmp     rdi, rsi
    je      .done

    ; check overlap
    mov     rcx, rsi
    add     rcx, rdx
    cmp     rdi, rsi
    jbe     .forward
    cmp     rdi, rcx
    jae     .forward

    ; --- Backward Copy Pathway ---
    mov     rcx, rdx
    shr     rcx, 4              ; count of 16-byte blocks
    jz      .residuals_back

    ; shift pointers to the end of raw buffers
    lea     rsi, [rsi + rdx]
    lea     rdi, [rdi + rdx]

    ; check if we can run unrolled backward loop (>= 64 bytes remaining)
    cmp     rdx, 64
    jb      .loop16_back_single

    mov     rcx, rdx
    shr     rcx, 6              ; count of 64-byte blocks

.loop16_back_unrolled:
    sub     rsi, 64
    sub     rdi, 64
    
    ; load 4 blocks (64 bytes total)
    movups  xmm0, [rsi + 48]
    movups  xmm1, [rsi + 32]
    movups  xmm2, [rsi + 16]
    movups  xmm3, [rsi]

    ; store 4 blocks
    movups  [rdi + 48], xmm0
    movups  [rdi + 32], xmm1
    movups  [rdi + 16], xmm2
    movups  [rdi], xmm3

    dec     rcx
    jnz     .loop16_back_unrolled

    and     rdx, 63             ; remaining bytes
    mov     rcx, rdx
    shr     rcx, 4
    jz      .residuals_back_setup

.loop16_back_single:
    sub     rsi, 16
    sub     rdi, 16
    movups  xmm0, [rsi]
    movups  [rdi], xmm0
    dec     rcx
    jnz     .loop16_back_single

.residuals_back_setup:
    and     rdx, 15
    jz      .done

    ; reset pointers to original positions + remaining size for final residuals
    sub     rsi, rdx
    sub     rdi, rdx

.residuals_back:
    std
    lea     rsi, [rsi + rdx - 1]
    lea     rdi, [rdi + rdx - 1]
    mov     rcx, rdx
    rep     movsb
    cld
    ret

.forward:
    ; forward copy has no overlap issue, delegate to optimized forward memcpy
    push    rdi
    push    rsi
    push    rdx
    call    umath_memcpy_sse
    pop     rdx
    pop     rsi
    pop     rdi
.done:
    ret

; -----------------------------------------------------------------------------
; umath_memmove_avx2 - overlap-safe memory move using 32-byte AVX2 blocks
; args:    rdi = destination address
;          rsi = source address
;          rdx = count in bytes
; returns: rax = destination address
; -----------------------------------------------------------------------------
global umath_memmove_avx2
umath_memmove_avx2:
    mov     rax, rdi
    test    rdx, rdx
    jz      .done
    cmp     rdi, rsi
    je      .done

    ; check overlap
    mov     rcx, rsi
    add     rcx, rdx
    cmp     rdi, rsi
    jbe     .forward
    cmp     rdi, rcx
    jae     .forward

    ; --- Backward Copy Pathway (AVX2) ---
    mov     rcx, rdx
    shr     rcx, 5              ; count of 32-byte blocks
    jz      .sse_fallback_back

    lea     rsi, [rsi + rdx]
    lea     rdi, [rdi + rdx]

    ; check if we can run unrolled backward loop (>= 128 bytes remaining)
    cmp     rdx, 128
    jb      .loop32_back_single

    mov     rcx, rdx
    shr     rcx, 7              ; count of 128-byte blocks

.loop32_back_unrolled:
    sub     rsi, 128
    sub     rdi, 128

    ; load 4 blocks (128 bytes total)
    vmovdqu ymm0, [rsi + 96]
    vmovdqu ymm1, [rsi + 64]
    vmovdqu ymm2, [rsi + 32]
    vmovdqu ymm3, [rsi]

    ; store 4 blocks
    vmovdqu [rdi + 96], ymm0
    vmovdqu [rdi + 64], ymm1
    vmovdqu [rdi + 32], ymm2
    vmovdqu [rdi], ymm3

    dec     rcx
    jnz     .loop32_back_unrolled

    and     rdx, 127
    mov     rcx, rdx
    shr     rcx, 5
    jz      .sse_fallback_back_setup

.loop32_back_single:
    sub     rsi, 32
    sub     rdi, 32
    vmovdqu ymm0, [rsi]
    vmovdqu [rdi], ymm0
    dec     rcx
    jnz     .loop32_back_single

.sse_fallback_back_setup:
    and     rdx, 31
    jz      .done_avx

    sub     rsi, rdx
    sub     rdi, rdx

.sse_fallback_back:
    cmp     rdx, 16
    jb      .residuals_back
    sub     rdx, 16
    movups  xmm0, [rsi + rdx]
    movups  [rdi + rdx], xmm0

.residuals_back:
    test    rdx, rdx
    jz      .done_avx
    std
    lea     rsi, [rsi + rdx - 1]
    lea     rdi, [rdi + rdx - 1]
    mov     rcx, rdx
    rep     movsb
    cld
    ret

.forward:
    push    rdi
    push    rsi
    push    rdx
    call    umath_memcpy_avx2
    pop     rdx
    pop     rsi
    pop     rdi
.done_avx:
    vzeroupper
.done:
    ret
