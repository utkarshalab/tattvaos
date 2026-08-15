%ifndef GUARD_LIB_UMATH_MEMORY_FILL_PATTERN_ASM
%define GUARD_LIB_UMATH_MEMORY_FILL_PATTERN_ASM
; =============================================================================
; umath - unified math library
; memory/fill_pattern.asm - optimized repeating pattern memory fill
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; Optimizations:
;   - Broadcasts user pattern (2, 4, 8, 16, or 32 bytes) across full width of SIMD
;     registers (SSE/AVX2).
;   - Loop unrolling (4x) in the main iteration path.
;   - Precise residual element/byte copying when sizes are not multiples of the
;     vector width or pattern width.
; =============================================================================

bits 64
section .text

; -----------------------------------------------------------------------------
; umath_memfill_pattern2 - fill buffer with a repeating 16-bit word
; args:    rdi = destination address
;          rsi = 16-bit pattern (low 16 bits of rsi)
;          rdx = size of buffer in bytes
; returns: rax = destination address
; -----------------------------------------------------------------------------
global umath_memfill_pattern2
umath_memfill_pattern2:
    mov     rax, rdi
    test    rdx, rdx
    jz      .done_p2

    ; broadcast 16-bit value to XMM0
    movzx   ecx, si
    movd    xmm0, ecx
    pinsrw  xmm0, ecx, 1
    pinsrw  xmm0, ecx, 2
    pinsrw  xmm0, ecx, 3
    pinsrw  xmm0, ecx, 4
    pinsrw  xmm0, ecx, 5
    pinsrw  xmm0, ecx, 6
    pinsrw  xmm0, ecx, 7        ; xmm0 = repeating 16-bit pattern

    ; loop unrolled 4x (64 bytes total per iteration)
    cmp     rdx, 64
    jb      .single_p2

    mov     rcx, rdx
    shr     rcx, 6              ; count of 64-byte chunks

.loop64_p2:
    movups  [rdi], xmm0
    movups  [rdi + 16], xmm0
    movups  [rdi + 32], xmm0
    movups  [rdi + 48], xmm0
    add     rdi, 64
    dec     rcx
    jnz     .loop64_p2

    and     rdx, 63

.single_p2:
    cmp     rdx, 16
    jb      .word_residuals

    mov     rcx, rdx
    shr     rcx, 4              ; count of 16-byte blocks

.loop16_p2:
    movups  [rdi], xmm0
    add     rdi, 16
    dec     rcx
    jnz     .loop16_p2

    and     rdx, 15

.word_residuals:
    ; copy final 16-bit words
    mov     rcx, rdx
    shr     rcx, 1              ; count of words
    jz      .byte_residuals

.loop_word_p2:
    mov     [rdi], si
    add     rdi, 2
    dec     rcx
    jnz     .loop_word_p2

    and     rdx, 1

.byte_residuals:
    ; copy final single byte (if buffer size was odd)
    test    rdx, rdx
    jz      .done_p2
    mov     [rdi], sil          ; low byte of pattern
.done_p2:
    ret

; -----------------------------------------------------------------------------
; umath_memfill_pattern4 - fill buffer with a repeating 32-bit dword
; args:    rdi = destination address
;          rsi = 32-bit pattern (low 32 bits of rsi)
;          rdx = size of buffer in bytes
; returns: rax = destination address
; -----------------------------------------------------------------------------
global umath_memfill_pattern4
umath_memfill_pattern4:
    mov     rax, rdi
    test    rdx, rdx
    jz      .done_p4

    ; broadcast 32-bit value to YMM0 (AVX2)
    mov     ecx, esi
    vmovd   xmm0, ecx
    vpbroadcastd ymm0, xmm0

    cmp     rdx, 128
    jb      .single_p4

    mov     rcx, rdx
    shr     rcx, 7              ; count of 128-byte chunks

.loop128_p4:
    vmovdqu [rdi], ymm0
    vmovdqu [rdi + 32], ymm0
    vmovdqu [rdi + 64], ymm0
    vmovdqu [rdi + 96], ymm0
    add     rdi, 128
    dec     rcx
    jnz     .loop128_p4

    and     rdx, 127

.single_p4:
    cmp     rdx, 32
    jb      .sse_fallback_p4

    mov     rcx, rdx
    shr     rcx, 5              ; count of 32-byte blocks

.loop32_p4:
    vmovdqu [rdi], ymm0
    add     rdi, 32
    dec     rcx
    jnz     .loop32_p4

    and     rdx, 31

.sse_fallback_p4:
    cmp     rdx, 16
    jb      .dword_residuals
    
    vextracti128 xmm1, ymm0, 0
    movups  [rdi], xmm1
    add     rdi, 16
    sub     rdx, 16

.dword_residuals:
    mov     rcx, rdx
    shr     rcx, 2              ; count of dwords
    jz      .byte_residuals

.loop_dword_p4:
    mov     [rdi], esi
    add     rdi, 4
    dec     rcx
    jnz     .loop_dword_p4

    and     rdx, 3

.byte_residuals:
    test    rdx, rdx
    jz      .done_p4
    
    ; write byte residual
    mov     rcx, rdx
.loop_byte_p4:
    mov     eax, esi
    ; determine which byte of the 4-byte pattern to write depending on offset
    ; but since it is a repeating pattern, byte i of buffer should receive pattern[offset % 4]
    ; wait, we can just do a small byte loop shifting esi
    mov     [rdi], al
    shr     esi, 8
    inc     rdi
    dec     rcx
    jnz     .loop_byte_p4

.done_p4:
    vzeroupper
    ret

; -----------------------------------------------------------------------------
; umath_memfill_pattern8 - fill buffer with a repeating 64-bit qword
; args:    rdi = destination address
;          rsi = 64-bit pattern
;          rdx = size of buffer in bytes
; returns: rax = destination address
; -----------------------------------------------------------------------------
global umath_memfill_pattern8
umath_memfill_pattern8:
    mov     rax, rdi
    test    rdx, rdx
    jz      .done_p8

    ; broadcast 64-bit value to YMM0
    vmovq   xmm0, rsi
    vpbroadcastq ymm0, xmm0

    cmp     rdx, 128
    jb      .single_p8

    mov     rcx, rdx
    shr     rcx, 7

.loop128_p8:
    vmovdqu [rdi], ymm0
    vmovdqu [rdi + 32], ymm0
    vmovdqu [rdi + 64], ymm0
    vmovdqu [rdi + 96], ymm0
    add     rdi, 128
    dec     rcx
    jnz     .loop128_p8

    and     rdx, 127

.single_p8:
    cmp     rdx, 32
    jb      .sse_fallback_p8

    mov     rcx, rdx
    shr     rcx, 5

.loop32_p8:
    vmovdqu [rdi], ymm0
    add     rdi, 32
    dec     rcx
    jnz     .loop32_p8

    and     rdx, 31

.sse_fallback_p8:
    cmp     rdx, 16
    jb      .qword_residuals
    vextracti128 xmm1, ymm0, 0
    movups  [rdi], xmm1
    add     rdi, 16
    sub     rdx, 16

.qword_residuals:
    mov     rcx, rdx
    shr     rcx, 3              ; count of qwords
    jz      .byte_residuals

.loop_qword_p8:
    mov     [rdi], rsi
    add     rdi, 8
    dec     rcx
    jnz     .loop_qword_p8

    and     rdx, 7

.byte_residuals:
    test    rdx, rdx
    jz      .done_p8
    mov     rcx, rdx
.loop_byte_p8:
    mov     rax, rsi
    mov     [rdi], al
    shr     rsi, 8
    inc     rdi
    dec     rcx
    jnz     .loop_byte_p8

.done_p8:
    vzeroupper
    ret

; -----------------------------------------------------------------------------
; umath_memfill_pattern16 - fill buffer with a repeating 128-bit pattern (XMM)
; args:    rdi = destination address
;          rsi = pointer to 128-bit pattern source location
;          rdx = size of buffer in bytes
; returns: rax = destination address
; -----------------------------------------------------------------------------
global umath_memfill_pattern16
umath_memfill_pattern16:
    mov     rax, rdi
    test    rdx, rdx
    jz      .done_p16
    test    rsi, rsi
    jz      .done_p16

    ; load 128-bit pattern into XMM0
    movups  xmm0, [rsi]

    cmp     rdx, 64
    jb      .single_p16

    mov     rcx, rdx
    shr     rcx, 6              ; count of 64-byte blocks

.loop64_p16:
    movups  [rdi], xmm0
    movups  [rdi + 16], xmm0
    movups  [rdi + 32], xmm0
    movups  [rdi + 48], xmm0
    add     rdi, 64
    dec     rcx
    jnz     .loop64_p16

    and     rdx, 63

.single_p16:
    cmp     rdx, 16
    jb      .residuals_p16

    mov     rcx, rdx
    shr     rcx, 4

.loop16_p16:
    movups  [rdi], xmm0
    add     rdi, 16
    dec     rcx
    jnz     .loop16_p16

    and     rdx, 15

.residuals_p16:
    test    rdx, rdx
    jz      .done_p16

    ; copy residual bytes of pattern
    ; load XMM0 to stack to access bytes cleanly
    sub     rsp, 16
    movups  [rsp], xmm0
    mov     rcx, rdx
    xor     r8, r8

.loop_res_p16:
    mov     al, [rsp + r8]
    mov     [rdi], al
    inc     rdi
    inc     r8
    dec     rcx
    jnz     .loop_res_p16
    
    add     rsp, 16

.done_p16:
    ret

; -----------------------------------------------------------------------------
; umath_memfill_pattern32 - fill buffer with a repeating 256-bit pattern (YMM)
; args:    rdi = destination address
;          rsi = pointer to 256-bit pattern source location
;          rdx = size of buffer in bytes
; returns: rax = destination address
; -----------------------------------------------------------------------------
global umath_memfill_pattern32
umath_memfill_pattern32:
    mov     rax, rdi
    test    rdx, rdx
    jz      .done_p32
    test    rsi, rsi
    jz      .done_p32

    ; load 256-bit pattern into YMM0
    vmovdqu ymm0, [rsi]

    cmp     rdx, 128
    jb      .single_p32

    mov     rcx, rdx
    shr     rcx, 7              ; count of 128-byte blocks

.loop128_p32:
    vmovdqu [rdi], ymm0
    vmovdqu [rdi + 32], ymm0
    vmovdqu [rdi + 64], ymm0
    vmovdqu [rdi + 96], ymm0
    add     rdi, 128
    dec     rcx
    jnz     .loop128_p32

    and     rdx, 127

.single_p32:
    cmp     rdx, 32
    jb      .sse_fallback_p32

    mov     rcx, rdx
    shr     rcx, 5

.loop32_p32:
    vmovdqu [rdi], ymm0
    add     rdi, 32
    dec     rcx
    jnz     .loop32_p32

    and     rdx, 31

.sse_fallback_p32:
    cmp     rdx, 16
    jb      .residuals_p32
    vextracti128 xmm1, ymm0, 0
    movups  [rdi], xmm1
    add     rdi, 16
    sub     rdx, 16

.residuals_p32:
    test    rdx, rdx
    jz      .done_p32

    ; copy residual bytes
    sub     rsp, 32
    vmovdqu [rsp], ymm0
    mov     rcx, rdx
    xor     r8, r8

.loop_res_p32:
    mov     al, [rsp + r8]
    mov     [rdi], al
    inc     rdi
    inc     r8
    dec     rcx
    jnz     .loop_res_p32

    add     rsp, 32

.done_p32:
    vzeroupper
    ret

%endif ; GUARD_LIB_UMATH_MEMORY_FILL_PATTERN_ASM
