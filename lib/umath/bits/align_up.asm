%ifndef GUARD_LIB_UMATH_BITS_ALIGN_UP_ASM
%define GUARD_LIB_UMATH_BITS_ALIGN_UP_ASM
; =============================================================================
; umath - unified math library
; bits/align_up.asm - round up to alignment boundary
; =============================================================================
; used for: arena allocators, SIMD-aligned buffer sizing, cache-line padding
; complements dtype_align.asm (which is dtype-aware) with generic
; alignment arithmetic for arbitrary power-of-2 alignments
;
; functions:
;   umath_align_up32       (val, align -> aligned value, u32)
;   umath_align_up64       (val, align -> aligned value, u64)
;   umath_align_up_ptr     (ptr, align -> aligned pointer)
;   umath_align_up_pad32   (val, align -> padding bytes needed, u32)
;   umath_align_up_pad64   (val, align -> padding bytes needed, u64)
;   umath_align_up_16      (val -> aligned to 16, XMM)
;   umath_align_up_32      (val -> aligned to 32, YMM)
;   umath_align_up_64      (val -> aligned to 64, ZMM/cache line)
;   umath_align_up_generic (val, align -> aligned, works for non-pow2 align too)
; =============================================================================

bits 64
section .text

; -----------------------------------------------------------------------------
; umath_align_up32 - round val up to nearest multiple of align (align = pow2)
; args:    edi = val
;          esi = align (must be power of 2)
; returns: eax = aligned value = (val + align - 1) & ~(align - 1)
; -----------------------------------------------------------------------------
global umath_align_up32
umath_align_up32:
    mov     eax, edi
    add     eax, esi
    dec     eax
    mov     ecx, esi
    dec     ecx
    not     ecx
    and     eax, ecx
    ret

; -----------------------------------------------------------------------------
; umath_align_up64 - round val up to nearest multiple of align (align = pow2)
; args:    rdi = val
;          rsi = align (must be power of 2)
; returns: rax = aligned value
; -----------------------------------------------------------------------------
global umath_align_up64
umath_align_up64:
    mov     rax, rdi
    add     rax, rsi
    dec     rax
    mov     rcx, rsi
    dec     rcx
    not     rcx
    and     rax, rcx
    ret

; -----------------------------------------------------------------------------
; umath_align_up_ptr - align a pointer up to given alignment (power of 2)
; args:    rdi = pointer
;          rsi = align (must be power of 2)
; returns: rax = aligned pointer (>= input pointer)
; -----------------------------------------------------------------------------
global umath_align_up_ptr
umath_align_up_ptr:
    mov     rax, rdi
    add     rax, rsi
    dec     rax
    mov     rcx, rsi
    dec     rcx
    not     rcx
    and     rax, rcx
    ret

; -----------------------------------------------------------------------------
; umath_align_up_pad32 - bytes of padding needed to reach next alignment
; args:    edi = val
;          esi = align (power of 2)
; returns: eax = padding = aligned(val) - val  (0 if already aligned)
; -----------------------------------------------------------------------------
global umath_align_up_pad32
umath_align_up_pad32:
    push    rbx
    mov     ebx, edi
    call    umath_align_up32
    sub     eax, ebx
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; umath_align_up_pad64 - bytes of padding needed to reach next alignment
; args:    rdi = val
;          rsi = align (power of 2)
; returns: rax = padding = aligned(val) - val
; -----------------------------------------------------------------------------
global umath_align_up_pad64
umath_align_up_pad64:
    push    rbx
    mov     rbx, rdi
    call    umath_align_up64
    sub     rax, rbx
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; umath_align_up_16 - round up to 16-byte boundary (XMM alignment)
; args:    rdi = val
; returns: rax = (val + 15) & ~15
; -----------------------------------------------------------------------------
global umath_align_up_16
umath_align_up_16:
    lea     rax, [rdi + 15]
    and     rax, ~15
    ret

; -----------------------------------------------------------------------------
; umath_align_up_32 - round up to 32-byte boundary (YMM alignment)
; args:    rdi = val
; returns: rax = (val + 31) & ~31
; -----------------------------------------------------------------------------
global umath_align_up_32
umath_align_up_32:
    lea     rax, [rdi + 31]
    and     rax, ~31
    ret

; -----------------------------------------------------------------------------
; umath_align_up_64 - round up to 64-byte boundary (ZMM / cache line)
; args:    rdi = val
; returns: rax = (val + 63) & ~63
; -----------------------------------------------------------------------------
global umath_align_up_64
umath_align_up_64:
    lea     rax, [rdi + 63]
    and     rax, ~63
    ret

; -----------------------------------------------------------------------------
; umath_align_up_generic - round val up to multiple of align (any align >= 1,
; not necessarily power of 2)
; args:    rdi = val
;          rsi = align (>= 1; align==0 returns val unchanged)
; returns: rax = ceil(val / align) * align
; algorithm: ((val + align - 1) / align) * align  using DIV
; -----------------------------------------------------------------------------
global umath_align_up_generic
umath_align_up_generic:
    test    rsi, rsi
    jz      .passthrough
    mov     rax, rdi
    add     rax, rsi
    dec     rax
    xor     rdx, rdx
    div     rsi                 ; rax = (val+align-1) / align
    imul    rax, rsi
    ret
.passthrough:
    mov     rax, rdi
    ret
%endif ; GUARD_LIB_UMATH_BITS_ALIGN_UP_ASM
