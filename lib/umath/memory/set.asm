%ifndef GUARD_LIB_UMATH_MEMORY_SET_ASM
%define GUARD_LIB_UMATH_MEMORY_SET_ASM
; =============================================================================
; umath - unified math library
; memory/set.asm - highly optimized memory fill (memset) implementations
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; Performance Optimizations:
;   - Loop unrolling (4x) in SSE, AVX2, and AVX-512 pathways to saturate memory
;     bus write ports and maximize write throughput.
;   - Byte broadcasting: duplicates the 8-bit fill value across the full width
;     of registers (16, 32, or 64 bytes) using efficient vector broadcast logic.
; =============================================================================

bits 64
section .text

; -----------------------------------------------------------------------------
; umath_memset - standard baseline memory fill (rep stosb)
; args:    rdi = destination address
;          rsi = fill byte value (low 8 bits)
;          rdx = size in bytes
; returns: rax = original destination address
; -----------------------------------------------------------------------------
global umath_memset
umath_memset:
    mov     rax, rdi            ; return value is original destination pointer
    mov     rcx, rdx
    mov     r8, rdi             ; preserve destination
    mov     al, sil             ; load fill value into al
    
    ; rep stosb is optimized via ERMS (Enhanced Rep Stosb) on modern processors
    rep     stosb
    mov     rax, r8
    ret

; -----------------------------------------------------------------------------
; umath_memset_sse - fill using unrolled SSE 16-byte stores
; args:    rdi = destination address
;          rsi = fill byte value
;          rdx = size in bytes
; returns: rax = original destination address
; -----------------------------------------------------------------------------
global umath_memset_sse
umath_memset_sse:
    mov     rax, rdi
    cmp     rdx, 16
    jb      .residuals

    ; broadcast byte value to xmm0
    movzx   ecx, sil
    movd    xmm0, ecx
    punpcklbw xmm0, xmm0        ; duplicate bytes to words
    pshuflw xmm0, xmm0, 0       ; duplicate words to dwords
    punpcklqdq xmm0, xmm0       ; duplicate dwords to qwords

    ; check if block size is large enough to unroll (>= 64 bytes)
    cmp     rdx, 64
    jb      .loop16_single

    mov     rcx, rdx
    shr     rcx, 6              ; count of 64-byte blocks (4x 16-byte blocks)

.loop16_unrolled:
    movups  [rdi], xmm0
    movups  [rdi + 16], xmm0
    movups  [rdi + 32], xmm0
    movups  [rdi + 48], xmm0
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
    movups  [rdi], xmm0
    add     rdi, 16
    dec     rcx
    jnz     .loop16_single_run

    and     rdx, 15
.residuals:
    test    rdx, rdx
    jz      .done
    mov     rcx, rdx
    mov     al, sil
    rep     stosb

.done:
    ret

; -----------------------------------------------------------------------------
; umath_memset_avx2 - fill using unrolled AVX2 32-byte stores
; args:    rdi = destination address
;          rsi = fill byte value
;          rdx = size in bytes
; returns: rax = original destination address
; -----------------------------------------------------------------------------
global umath_memset_avx2
umath_memset_avx2:
    mov     rax, rdi
    cmp     rdx, 32
    jb      .sse_fallback

    ; broadcast byte value to ymm0
    movzx   ecx, sil
    vmovd   xmm0, ecx
    vpbroadcastb ymm0, xmm0

    ; check if size is large enough to unroll (>= 128 bytes)
    cmp     rdx, 128
    jb      .loop32_single

    mov     rcx, rdx
    shr     rcx, 7              ; count of 128-byte blocks (4x 32-byte blocks)

.loop32_unrolled:
    vmovdqu [rdi], ymm0
    vmovdqu [rdi + 32], ymm0
    vmovdqu [rdi + 64], ymm0
    vmovdqu [rdi + 96], ymm0
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
    vmovdqu [rdi], ymm0
    add     rdi, 32
    dec     rcx
    jnz     .loop32_single_run

    and     rdx, 31
.sse_fallback:
    cmp     rdx, 16
    jb      .residuals
    
    ; broadcast byte to xmm0
    movzx   ecx, sil
    movd    xmm0, ecx
    punpcklbw xmm0, xmm0
    pshuflw xmm0, xmm0, 0
    punpcklqdq xmm0, xmm0
    movups  [rdi], xmm0
    add     rdi, 16
    sub     rdx, 16

.residuals:
    test    rdx, rdx
    jz      .done
    mov     rcx, rdx
    mov     al, sil
    rep     stosb

.done:
    vzeroupper
    ret

; -----------------------------------------------------------------------------
; umath_memset_avx512 - fill using unrolled AVX-512 64-byte stores
; args:    rdi = destination address
;          rsi = fill byte value
;          rdx = size in bytes
; returns: rax = original destination address
; -----------------------------------------------------------------------------
global umath_memset_avx512
umath_memset_avx512:
    mov     rax, rdi
    cmp     rdx, 64
    jb      .avx2_fallback

    ; broadcast byte value to zmm0
    movzx   ecx, sil
    vmovd   xmm0, ecx
    vpbroadcastb zmm0, xmm0

    ; check if size is large enough to unroll (>= 256 bytes)
    cmp     rdx, 256
    jb      .loop64_single

    mov     rcx, rdx
    shr     rcx, 8              ; count of 256-byte blocks (4x 64-byte blocks)

.loop64_unrolled:
    vmovdqu64 [rdi], zmm0
    vmovdqu64 [rdi + 64], zmm0
    vmovdqu64 [rdi + 128], zmm0
    vmovdqu64 [rdi + 192], zmm0
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
    vmovdqu64 [rdi], zmm0
    add     rdi, 64
    dec     rcx
    jnz     .loop64_single_run

    and     rdx, 63
.avx2_fallback:
    cmp     rdx, 32
    jb      .sse_fallback
    movzx   ecx, sil
    vmovd   xmm0, ecx
    vpbroadcastb ymm0, xmm0
    vmovdqu [rdi], ymm0
    add     rdi, 32
    sub     rdx, 32

.sse_fallback:
    cmp     rdx, 16
    jb      .residuals
    movzx   ecx, sil
    movd    xmm0, ecx
    punpcklbw xmm0, xmm0
    pshuflw xmm0, xmm0, 0
    punpcklqdq xmm0, xmm0
    movups  [rdi], xmm0
    add     rdi, 16
    sub     rdx, 16

.residuals:
    test    rdx, rdx
    jz      .done
    mov     rcx, rdx
    mov     al, sil
    rep     stosb

.done:
    vzeroupper
    ret

%endif ; GUARD_LIB_UMATH_MEMORY_SET_ASM
