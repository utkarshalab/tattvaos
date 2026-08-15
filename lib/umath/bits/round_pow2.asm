%ifndef GUARD_LIB_UMATH_BITS_ROUND_POW2_ASM
%define GUARD_LIB_UMATH_BITS_ROUND_POW2_ASM
; =============================================================================
; umath - unified math library
; bits/round_pow2.asm - power-of-two rounding operations
; =============================================================================
; used for: allocator size classes, hash table sizing, FFT length selection,
;           tensor padding to SIMD-friendly sizes
;
; functions:
;   umath_round_pow2_up32     (val -> next power of 2 >= val, u32)
;   umath_round_pow2_up64     (val -> next power of 2 >= val, u64)
;   umath_round_pow2_down32   (val -> largest power of 2 <= val, u32)
;   umath_round_pow2_down64   (val -> largest power of 2 <= val, u64)
;   umath_is_pow2_32          (val -> 0/1)
;   umath_is_pow2_64          (val -> 0/1)
;   umath_log2_floor32        (val -> floor(log2(val)), or -1 if val==0)
;   umath_log2_floor64        (val -> floor(log2(val)), or -1 if val==0)
;   umath_log2_ceil32         (val -> ceil(log2(val)), or -1 if val==0)
;   umath_log2_ceil64         (val -> ceil(log2(val)), or -1 if val==0)
;   umath_pow2_32             (n -> 2^n, u32; n in 0-31)
;   umath_pow2_64             (n -> 2^n, u64; n in 0-63)
; =============================================================================

bits 64
section .text

; -----------------------------------------------------------------------------
; umath_round_pow2_up32 - smallest power of 2 >= val (32-bit)
; args:    edi = val
; returns: eax = next power of 2 (0 if val==0 -> returns 1; saturates at
;          0x80000000 if val > 0x80000000)
; algorithm: classic bit-smear: dec, OR-shift cascade, inc
; -----------------------------------------------------------------------------
global umath_round_pow2_up32
umath_round_pow2_up32:
    mov     eax, edi
    cmp     eax, 1
    jle     .one_or_zero
    dec     eax
    mov     ecx, eax
    shr     ecx, 1
    or      eax, ecx
    mov     ecx, eax
    shr     ecx, 2
    or      eax, ecx
    mov     ecx, eax
    shr     ecx, 4
    or      eax, ecx
    mov     ecx, eax
    shr     ecx, 8
    or      eax, ecx
    mov     ecx, eax
    shr     ecx, 16
    or      eax, ecx
    inc     eax
    ret
.one_or_zero:
    mov     eax, 1
    ret

; -----------------------------------------------------------------------------
; umath_round_pow2_up64 - smallest power of 2 >= val (64-bit)
; args:    rdi = val
; returns: rax = next power of 2
; -----------------------------------------------------------------------------
global umath_round_pow2_up64
umath_round_pow2_up64:
    mov     rax, rdi
    cmp     rax, 1
    jle     .one_or_zero
    dec     rax
    mov     rcx, rax
    shr     rcx, 1
    or      rax, rcx
    mov     rcx, rax
    shr     rcx, 2
    or      rax, rcx
    mov     rcx, rax
    shr     rcx, 4
    or      rax, rcx
    mov     rcx, rax
    shr     rcx, 8
    or      rax, rcx
    mov     rcx, rax
    shr     rcx, 16
    or      rax, rcx
    mov     rcx, rax
    shr     rcx, 32
    or      rax, rcx
    inc     rax
    ret
.one_or_zero:
    mov     rax, 1
    ret

; -----------------------------------------------------------------------------
; umath_round_pow2_down32 - largest power of 2 <= val (32-bit)
; args:    edi = val (must be >= 1; val==0 returns 0)
; returns: eax = largest power of 2 <= val
; algorithm: 1 << floor(log2(val)) via BSR
; -----------------------------------------------------------------------------
global umath_round_pow2_down32
umath_round_pow2_down32:
    test    edi, edi
    jz      .zero
    bsr     ecx, edi
    mov     eax, 1
    shl     eax, cl
    ret
.zero:
    xor     eax, eax
    ret

; -----------------------------------------------------------------------------
; umath_round_pow2_down64 - largest power of 2 <= val (64-bit)
; args:    rdi = val (val==0 returns 0)
; returns: rax = largest power of 2 <= val
; -----------------------------------------------------------------------------
global umath_round_pow2_down64
umath_round_pow2_down64:
    test    rdi, rdi
    jz      .zero
    bsr     rcx, rdi
    mov     rax, 1
    shl     rax, cl
    ret
.zero:
    xor     eax, eax
    ret

; -----------------------------------------------------------------------------
; umath_is_pow2_32 - check if val is exactly a power of two
; args:    edi = val
; returns: eax = 1 if val is a power of 2 (and val != 0), 0 otherwise
; algorithm: val != 0 && (val & (val-1)) == 0
; -----------------------------------------------------------------------------
global umath_is_pow2_32
umath_is_pow2_32:
    test    edi, edi
    jz      .no
    lea     eax, [edi - 1]
    and     eax, edi
    test    eax, eax
    setz    al
    movzx   eax, al
    ret
.no:
    xor     eax, eax
    ret

; -----------------------------------------------------------------------------
; umath_is_pow2_64 - check if val is exactly a power of two (64-bit)
; args:    rdi = val
; returns: eax = 1 if power of 2, 0 otherwise
; -----------------------------------------------------------------------------
global umath_is_pow2_64
umath_is_pow2_64:
    test    rdi, rdi
    jz      .no
    lea     rax, [rdi - 1]
    and     rax, rdi
    test    rax, rax
    setz    al
    movzx   eax, al
    ret
.no:
    xor     eax, eax
    ret

; -----------------------------------------------------------------------------
; umath_log2_floor32 - floor(log2(val)) for val > 0
; args:    edi = val
; returns: eax = bit position of highest set bit, or -1 if val==0
; -----------------------------------------------------------------------------
global umath_log2_floor32
umath_log2_floor32:
    test    edi, edi
    jz      .zero
    bsr     eax, edi
    ret
.zero:
    mov     eax, -1
    ret

; -----------------------------------------------------------------------------
; umath_log2_floor64 - floor(log2(val)) for val > 0
; args:    rdi = val
; returns: eax = bit position of highest set bit, or -1 if val==0
; -----------------------------------------------------------------------------
global umath_log2_floor64
umath_log2_floor64:
    test    rdi, rdi
    jz      .zero
    bsr     rax, rdi
    ret
.zero:
    mov     eax, -1
    ret

; -----------------------------------------------------------------------------
; umath_log2_ceil32 - ceil(log2(val)) for val > 0
; args:    edi = val
; returns: eax = ceil(log2(val)), or -1 if val==0
; algorithm: floor_log2 + (1 if not exact power of 2 else 0)
; -----------------------------------------------------------------------------
global umath_log2_ceil32
umath_log2_ceil32:
    test    edi, edi
    jz      .zero
    bsr     eax, edi
    ; check if exact power of 2
    lea     ecx, [edi - 1]
    and     ecx, edi
    test    ecx, ecx
    jz      .done            ; exact power of 2: ceil == floor
    inc     eax
.done:
    ret
.zero:
    mov     eax, -1
    ret

; -----------------------------------------------------------------------------
; umath_log2_ceil64 - ceil(log2(val)) for val > 0
; args:    rdi = val
; returns: eax = ceil(log2(val)), or -1 if val==0
; -----------------------------------------------------------------------------
global umath_log2_ceil64
umath_log2_ceil64:
    test    rdi, rdi
    jz      .zero
    bsr     rax, rdi
    lea     rcx, [rdi - 1]
    and     rcx, rdi
    test    rcx, rcx
    jz      .done
    inc     eax
.done:
    ret
.zero:
    mov     eax, -1
    ret

; -----------------------------------------------------------------------------
; umath_pow2_32 - compute 2^n
; args:    edi = n (0-31)
; returns: eax = 2^n (undefined if n > 31, masked to 0-31)
; -----------------------------------------------------------------------------
global umath_pow2_32
umath_pow2_32:
    mov     ecx, edi
    and     ecx, 31
    mov     eax, 1
    shl     eax, cl
    ret

; -----------------------------------------------------------------------------
; umath_pow2_64 - compute 2^n
; args:    rdi = n (0-63)
; returns: rax = 2^n (masked to 0-63)
; -----------------------------------------------------------------------------
global umath_pow2_64
umath_pow2_64:
    mov     ecx, edi
    and     ecx, 63
    mov     rax, 1
    shl     rax, cl
    ret
%endif ; GUARD_LIB_UMATH_BITS_ROUND_POW2_ASM
