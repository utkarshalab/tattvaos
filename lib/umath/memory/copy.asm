; =============================================================================
; umath - unified math library
; memory/copy.asm - highly optimized SIMD-aware memory copy (memcpy)
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; Performance Optimizations:
;   - Loop unrolling (4x) in SSE, AVX2, and AVX-512 pathways to maximize CPU
;     execution port usage and instruction-level parallelism.
;   - Non-temporal (NT) cache-bypassing writes (movntdq) in aligned pathways
;     to avoid L1/L2/L3 cache pollution when copying large blocks.
;   - Graceful fallback sequence matching CPU features and block sizes.
; =============================================================================

bits 64
section .text

; -----------------------------------------------------------------------------
; umath_memcpy - standard byte-by-byte baseline copy (rep movsb)
; args:    rdi = destination address
;          rsi = source address
;          rdx = count in bytes
; returns: rax = destination address
; -----------------------------------------------------------------------------
global umath_memcpy
umath_memcpy:
    mov     rax, rdi            ; return value is original destination
    mov     rcx, rdx
    
    ; rep movsb is highly optimized on modern x86 (ERMS - Enhanced Rep Movsb)
    rep     movsb
    ret

; -----------------------------------------------------------------------------
; umath_memcpy_sse - copy using unrolled SSE 16-byte blocks
; args:    rdi = destination address
;          rsi = source address
;          rdx = count in bytes
; returns: rax = destination address
; -----------------------------------------------------------------------------
global umath_memcpy_sse
umath_memcpy_sse:
    mov     rax, rdi
    
    ; check if size is smaller than a single 16-byte block
    cmp     rdx, 16
    jb      .residuals

    ; check if size is large enough to warrant unrolled loop (>= 64 bytes)
    cmp     rdx, 64
    jb      .loop16_single

    mov     rcx, rdx
    shr     rcx, 6              ; count of 64-byte blocks (4x 16-byte blocks)

.loop16_unrolled:
    ; load 4 blocks (64 bytes total)
    movups  xmm0, [rsi]
    movups  xmm1, [rsi + 16]
    movups  xmm2, [rsi + 32]
    movups  xmm3, [rsi + 48]

    ; store 4 blocks
    movups  [rdi], xmm0
    movups  [rdi + 16], xmm1
    movups  [rdi + 32], xmm2
    movups  [rdi + 48], xmm3

    add     rsi, 64
    add     rdi, 64
    dec     rcx
    jnz     .loop16_unrolled

    and     rdx, 63             ; remaining bytes
    cmp     rdx, 16
    jb      .residuals

.loop16_single:
    mov     rcx, rdx
    shr     rcx, 4              ; count of remaining 16-byte blocks

.loop16_single_run:
    movups  xmm0, [rsi]
    movups  [rdi], xmm0
    add     rsi, 16
    add     rdi, 16
    dec     rcx
    jnz     .loop16_single_run

    and     rdx, 15             ; remaining bytes < 16
.residuals:
    test    rdx, rdx
    jz      .done
    
    ; copy byte-by-byte for final residuals
    mov     rcx, rdx
    rep     movsb

.done:
    ret

; -----------------------------------------------------------------------------
; umath_memcpy_avx2 - copy using unrolled AVX2 32-byte blocks
; args:    rdi = destination address
;          rsi = source address
;          rdx = count in bytes
; returns: rax = destination address
; -----------------------------------------------------------------------------
global umath_memcpy_avx2
umath_memcpy_avx2:
    mov     rax, rdi
    
    ; check fallback thresholds
    cmp     rdx, 32
    jb      .sse_fallback

    cmp     rdx, 128
    jb      .loop32_single

    mov     rcx, rdx
    shr     rcx, 7              ; count of 128-byte blocks (4x 32-byte blocks)

.loop32_unrolled:
    ; load 4 blocks (128 bytes total)
    vmovdqu ymm0, [rsi]
    vmovdqu ymm1, [rsi + 32]
    vmovdqu ymm2, [rsi + 64]
    vmovdqu ymm3, [rsi + 96]

    ; store 4 blocks
    vmovdqu [rdi], ymm0
    vmovdqu [rdi + 32], ymm1
    vmovdqu [rdi + 64], ymm2
    vmovdqu [rdi + 96], ymm3

    add     rsi, 128
    add     rdi, 128
    dec     rcx
    jnz     .loop32_unrolled

    and     rdx, 127
    cmp     rdx, 32
    jb      .sse_fallback

.loop32_single:
    mov     rcx, rdx
    shr     rcx, 5              ; count of remaining 32-byte blocks

.loop32_single_run:
    vmovdqu ymm0, [rsi]
    vmovdqu [rdi], ymm0
    add     rsi, 32
    add     rdi, 32
    dec     rcx
    jnz     .loop32_single_run

    and     rdx, 31
.sse_fallback:
    cmp     rdx, 16
    jb      .residuals
    
    movups  xmm0, [rsi]
    movups  [rdi], xmm0
    add     rsi, 16
    add     rdi, 16
    sub     rdx, 16

.residuals:
    test    rdx, rdx
    jz      .done
    mov     rcx, rdx
    rep     movsb

.done:
    vzeroupper
    ret

; -----------------------------------------------------------------------------
; umath_memcpy_avx512 - copy using unrolled AVX-512 64-byte blocks
; args:    rdi = destination address
;          rsi = source address
;          rdx = count in bytes
; returns: rax = destination address
; -----------------------------------------------------------------------------
global umath_memcpy_avx512
umath_memcpy_avx512:
    mov     rax, rdi
    
    ; check threshold
    cmp     rdx, 64
    jb      .avx2_fallback

    cmp     rdx, 256
    jb      .loop64_single

    mov     rcx, rdx
    shr     rcx, 8              ; count of 256-byte blocks (4x 64-byte blocks)

.loop64_unrolled:
    ; load 4 blocks (256 bytes total)
    vmovdqu64 zmm0, [rsi]
    vmovdqu64 zmm1, [rsi + 64]
    vmovdqu64 zmm2, [rsi + 128]
    vmovdqu64 zmm3, [rsi + 192]

    ; store 4 blocks
    vmovdqu64 [rdi], zmm0
    vmovdqu64 [rdi + 64], zmm1
    vmovdqu64 [rdi + 128], zmm2
    vmovdqu64 [rdi + 192], zmm3

    add     rsi, 256
    add     rdi, 256
    dec     rcx
    jnz     .loop64_unrolled

    and     rdx, 255
    cmp     rdx, 64
    jb      .avx2_fallback

.loop64_single:
    mov     rcx, rdx
    shr     rcx, 6              ; count of remaining 64-byte blocks

.loop64_single_run:
    vmovdqu64 zmm0, [rsi]
    vmovdqu64 [rdi], zmm0
    add     rsi, 64
    add     rdi, 64
    dec     rcx
    jnz     .loop64_single_run

    and     rdx, 63
.avx2_fallback:
    cmp     rdx, 32
    jb      .sse_fallback
    vmovdqu ymm0, [rsi]
    vmovdqu [rdi], ymm0
    add     rsi, 32
    add     rdi, 32
    sub     rdx, 32

.sse_fallback:
    cmp     rdx, 16
    jb      .residuals
    movups  xmm0, [rsi]
    movups  [rdi], xmm0
    add     rsi, 16
    add     rdi, 16
    sub     rdx, 16

.residuals:
    test    rdx, rdx
    jz      .done
    mov     rcx, rdx
    rep     movsb

.done:
    vzeroupper
    ret

; -----------------------------------------------------------------------------
; umath_memcpy_aligned - copy aligned blocks using non-temporal streaming writes
; args:    rdi = destination address (must be aligned to 16 bytes minimum)
;          rsi = source address (must be aligned to 16 bytes minimum)
;          rdx = count in bytes
; returns: rax = destination address
; -----------------------------------------------------------------------------
global umath_memcpy_aligned
umath_memcpy_aligned:
    mov     rax, rdi
    
    ; check alignment assertions (if either pointer is unaligned, fallback to standard SSE)
    test    rdi, 15
    jnz     .fallback
    test    rsi, 15
    jnz     .fallback

    ; only use non-temporal writes for sufficiently large blocks to avoid cache-flush overheads
    cmp     rdx, 128
    jb      .normal_copy

    mov     rcx, rdx
    shr     rcx, 7              ; number of 128-byte chunks (8x 16-byte blocks)

.loop_nt_128:
    ; load 8 XMM blocks
    movaps  xmm0, [rsi]
    movaps  xmm1, [rsi + 16]
    movaps  xmm2, [rsi + 32]
    movaps  xmm3, [rsi + 48]
    movaps  xmm4, [rsi + 64]
    movaps  xmm5, [rsi + 80]
    movaps  xmm6, [rsi + 96]
    movaps  xmm7, [rsi + 112]

    ; non-temporal writes bypass L1/L2 cache and go straight to system memory
    movntdq [rdi], xmm0
    movntdq [rdi + 16], xmm1
    movntdq [rdi + 32], xmm2
    movntdq [rdi + 48], xmm3
    movntdq [rdi + 64], xmm4
    movntdq [rdi + 80], xmm5
    movntdq [rdi + 96], xmm6
    movntdq [rdi + 112], xmm7

    add     rsi, 128
    add     rdi, 128
    dec     rcx
    jnz     .loop_nt_128

    ; issue a store fence to ensure non-temporal writes are visible to other processors
    sfence

    and     rdx, 127
.normal_copy:
    cmp     rdx, 16
    jb      .residuals
    
    mov     rcx, rdx
    shr     rcx, 4

.loop_res16:
    movaps  xmm0, [rsi]
    movaps  [rdi], xmm0
    add     rsi, 16
    add     rdi, 16
    dec     rcx
    jnz     .loop_res16

    and     rdx, 15
.residuals:
    test    rdx, rdx
    jz      .done
    mov     rcx, rdx
    rep     movsb
    ret

.fallback:
    ; fallback to standard unaligned SSE copy
    push    rdi
    push    rsi
    push    rdx
    call    umath_memcpy_sse
    pop     rdx
    pop     rsi
    pop     rdi
.done:
    ret
