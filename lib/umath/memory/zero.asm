%ifndef GUARD_LIB_UMATH_MEMORY_ZERO_ASM
%define GUARD_LIB_UMATH_MEMORY_ZERO_ASM
; =============================================================================
; umath - unified math library
; memory/zero.asm - highly optimized memory zeroing (memzero)
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; Performance Optimizations:
;   - Loop unrolling (4x) in SSE, AVX2, and AVX-512 pathways to achieve maximum
;     fill rate and saturate system memory write ports.
;   - Non-temporal (NT) cache-bypassing zeroing (umath_memzero_nt) to zero
;     large arrays without clearing out active caches (L1/L2/L3).
; =============================================================================

bits 64
section .text

; -----------------------------------------------------------------------------
; umath_memzero - standard baseline memory zeroing (using rep stosb)
; args:    rdi = destination address
;          rsi = size in bytes
; returns: rax = original destination address
; -----------------------------------------------------------------------------
global umath_memzero
umath_memzero:
    mov     rax, rdi            ; return value is original destination pointer
    mov     rcx, rsi            ; count of bytes
    mov     r8, rdi             ; preserve destination
    xor     eax, eax            ; zero fill value
    rep     stosb
    mov     rax, r8
    ret

; -----------------------------------------------------------------------------
; umath_memzero_sse - zero memory using unrolled SSE 16-byte stores
; args:    rdi = destination address
;          rsi = size in bytes
; returns: rax = original destination address
; -----------------------------------------------------------------------------
global umath_memzero_sse
umath_memzero_sse:
    mov     rax, rdi
    cmp     rsi, 16
    jb      .residuals

    xorps   xmm0, xmm0          ; clear xmm0 to 0

    ; check if size is large enough to unroll (>= 64 bytes)
    cmp     rsi, 64
    jb      .loop16_single

    mov     rcx, rsi
    shr     rcx, 6              ; count of 64-byte blocks (4x 16-byte blocks)

.loop16_unrolled:
    movups  [rdi], xmm0
    movups  [rdi + 16], xmm0
    movups  [rdi + 32], xmm0
    movups  [rdi + 48], xmm0
    add     rdi, 64
    dec     rcx
    jnz     .loop16_unrolled

    and     rsi, 63             ; remaining bytes
    cmp     rsi, 16
    jb      .residuals

.loop16_single:
    mov     rcx, rsi
    shr     rcx, 4              ; count of remaining 16-byte blocks

.loop16_single_run:
    movups  [rdi], xmm0
    add     rdi, 16
    dec     rcx
    jnz     .loop16_single_run

    and     rsi, 15
.residuals:
    test    rsi, rsi
    jz      .done
    mov     rcx, rsi
    xor     eax, eax
    rep     stosb

.done:
    ret

; -----------------------------------------------------------------------------
; umath_memzero_avx2 - zero memory using unrolled AVX2 32-byte stores
; args:    rdi = destination address
;          rsi = size in bytes
; returns: rax = original destination address
; -----------------------------------------------------------------------------
global umath_memzero_avx2
umath_memzero_avx2:
    mov     rax, rdi
    cmp     rsi, 32
    jb      .sse_fallback

    vpxor   ymm0, ymm0, ymm0    ; clear ymm0 to 0

    ; check if size is large enough to unroll (>= 128 bytes)
    cmp     rsi, 128
    jb      .loop32_single

    mov     rcx, rsi
    shr     rcx, 7              ; count of 128-byte blocks (4x 32-byte blocks)

.loop32_unrolled:
    vmovdqu [rdi], ymm0
    vmovdqu [rdi + 32], ymm0
    vmovdqu [rdi + 64], ymm0
    vmovdqu [rdi + 96], ymm0
    add     rdi, 128
    dec     rcx
    jnz     .loop32_unrolled

    and     rsi, 127
    cmp     rsi, 32
    jb      .sse_fallback

.loop32_single:
    mov     rcx, rsi
    shr     rcx, 5              ; count of remaining 32-byte blocks

.loop32_single_run:
    vmovdqu [rdi], ymm0
    add     rdi, 32
    dec     rcx
    jnz     .loop32_single_run

    and     rsi, 31
.sse_fallback:
    cmp     rsi, 16
    jb      .residuals
    xorps   xmm0, xmm0
    movups  [rdi], xmm0
    add     rdi, 16
    sub     rsi, 16

.residuals:
    test    rsi, rsi
    jz      .done
    mov     rcx, rsi
    xor     eax, eax
    rep     stosb

.done:
    vzeroupper
    ret

; -----------------------------------------------------------------------------
; umath_memzero_avx512 - zero memory using unrolled AVX-512 64-byte stores
; args:    rdi = destination address
;          rsi = size in bytes
; returns: rax = original destination address
; -----------------------------------------------------------------------------
global umath_memzero_avx512
umath_memzero_avx512:
    mov     rax, rdi
    cmp     rsi, 64
    jb      .avx2_fallback

    vpxorq  zmm0, zmm0, zmm0    ; clear zmm0 to 0

    ; check if size is large enough to unroll (>= 256 bytes)
    cmp     rsi, 256
    jb      .loop64_single

    mov     rcx, rsi
    shr     rcx, 8              ; count of 256-byte blocks (4x 64-byte blocks)

.loop64_unrolled:
    vmovdqu64 [rdi], zmm0
    vmovdqu64 [rdi + 64], zmm0
    vmovdqu64 [rdi + 128], zmm0
    vmovdqu64 [rdi + 192], zmm0
    add     rdi, 256
    dec     rcx
    jnz     .loop64_unrolled

    and     rsi, 255
    cmp     rsi, 64
    jb      .avx2_fallback

.loop64_single:
    mov     rcx, rsi
    shr     rcx, 6              ; count of remaining 64-byte blocks

.loop64_single_run:
    vmovdqu64 [rdi], zmm0
    add     rdi, 64
    dec     rcx
    jnz     .loop64_single_run

    and     rsi, 63
.avx2_fallback:
    cmp     rsi, 32
    jb      .sse_fallback
    vpxor   ymm0, ymm0, ymm0
    vmovdqu [rdi], ymm0
    add     rdi, 32
    sub     rsi, 32

.sse_fallback:
    cmp     rsi, 16
    jb      .residuals
    xorps   xmm0, xmm0
    movups  [rdi], xmm0
    add     rdi, 16
    sub     rsi, 16

.residuals:
    test    rsi, rsi
    jz      .done
    mov     rcx, rsi
    xor     eax, eax
    rep     stosb

.done:
    vzeroupper
    ret

; -----------------------------------------------------------------------------
; umath_memzero_nt - non-temporal (cache-bypassing) zeroing for large blocks
; args:    rdi = destination address (must be aligned to 16 bytes minimum)
;          rsi = size in bytes
; returns: rax = original destination address
; -----------------------------------------------------------------------------
global umath_memzero_nt
umath_memzero_nt:
    mov     rax, rdi
    
    ; check alignment (if unaligned, fallback to standard SSE zeroing)
    test    rdi, 15
    jnz     .fallback

    ; only use NT writes for sufficiently large blocks to avoid cache-flush overheads
    cmp     rsi, 128
    jb      .normal_zero

    xorps   xmm0, xmm0          ; zero value

    mov     rcx, rsi
    shr     rcx, 7              ; number of 128-byte chunks (8x 16-byte blocks)

.loop_nt_128:
    ; non-temporal stores bypass cache
    movntdq [rdi], xmm0
    movntdq [rdi + 16], xmm0
    movntdq [rdi + 32], xmm0
    movntdq [rdi + 48], xmm0
    movntdq [rdi + 64], xmm0
    movntdq [rdi + 80], xmm0
    movntdq [rdi + 96], xmm0
    movntdq [rdi + 112], xmm0

    add     rdi, 128
    dec     rcx
    jnz     .loop_nt_128

    ; issue a store fence to ensure non-temporal writes are visible
    sfence

    and     rsi, 127
.normal_zero:
    cmp     rsi, 16
    jb      .residuals
    
    mov     rcx, rsi
    shr     rcx, 4
    xorps   xmm0, xmm0
.loop_res16:
    movaps  [rdi], xmm0
    add     rdi, 16
    dec     rcx
    jnz     .loop_res16

    and     rsi, 15
.residuals:
    test    rsi, rsi
    jz      .done
    mov     rcx, rsi
    xor     eax, eax
    rep     stosb
    ret

.fallback:
    ; fallback to standard unaligned SSE zeroing
    push    rdi
    push    rsi
    call    umath_memzero_sse
    pop     rsi
    pop     rdi
.done:
    ret

%endif ; GUARD_LIB_UMATH_MEMORY_ZERO_ASM
