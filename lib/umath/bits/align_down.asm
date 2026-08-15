%ifndef GUARD_LIB_UMATH_BITS_ALIGN_DOWN_ASM
%define GUARD_LIB_UMATH_BITS_ALIGN_DOWN_ASM
; =============================================================================
; umath - unified math library
; bits/align_down.asm - round down to alignment boundary
; =============================================================================
; used for: finding the start of the containing aligned block,
;           page-aligning addresses, truncating offsets to cache lines
;
; functions:
;   umath_align_down32       (val, align -> aligned value, u32)
;   umath_align_down64       (val, align -> aligned value, u64)
;   umath_align_down_ptr     (ptr, align -> aligned pointer, <= input)
;   umath_align_down_16      (val -> aligned down to 16, XMM)
;   umath_align_down_32      (val -> aligned down to 32, YMM)
;   umath_align_down_64      (val -> aligned down to 64, ZMM/cache line)
;   umath_align_down_generic (val, align -> aligned, works for non-pow2 align)
;   umath_is_aligned32       (val, align -> 0/1, align = pow2)
;   umath_is_aligned64       (val, align -> 0/1, align = pow2)
;   umath_is_aligned_ptr     (ptr, align -> 0/1, align = pow2)
;   umath_offset_in_block32  (val, align -> val mod align, align = pow2)
;   umath_offset_in_block64  (val, align -> val mod align, align = pow2)
; =============================================================================

bits 64
section .text

; -----------------------------------------------------------------------------
; umath_align_down32 - round val down to nearest multiple of align (pow2)
; args:    edi = val
;          esi = align (must be power of 2)
; returns: eax = aligned value = val & ~(align - 1)
; -----------------------------------------------------------------------------
global umath_align_down32
umath_align_down32:
    mov     eax, edi
    mov     ecx, esi
    dec     ecx
    not     ecx
    and     eax, ecx
    ret

; -----------------------------------------------------------------------------
; umath_align_down64 - round val down to nearest multiple of align (pow2)
; args:    rdi = val
;          rsi = align (must be power of 2)
; returns: rax = aligned value = val & ~(align - 1)
; -----------------------------------------------------------------------------
global umath_align_down64
umath_align_down64:
    mov     rax, rdi
    mov     rcx, rsi
    dec     rcx
    not     rcx
    and     rax, rcx
    ret

; -----------------------------------------------------------------------------
; umath_align_down_ptr - align a pointer down to given alignment (pow2)
; args:    rdi = pointer
;          rsi = align (must be power of 2)
; returns: rax = aligned pointer (<= input pointer)
; -----------------------------------------------------------------------------
global umath_align_down_ptr
umath_align_down_ptr:
    mov     rax, rdi
    mov     rcx, rsi
    dec     rcx
    not     rcx
    and     rax, rcx
    ret

; -----------------------------------------------------------------------------
; umath_align_down_16 - round down to 16-byte boundary (XMM alignment)
; args:    rdi = val
; returns: rax = val & ~15
; -----------------------------------------------------------------------------
global umath_align_down_16
umath_align_down_16:
    mov     rax, rdi
    and     rax, ~15
    ret

; -----------------------------------------------------------------------------
; umath_align_down_32 - round down to 32-byte boundary (YMM alignment)
; args:    rdi = val
; returns: rax = val & ~31
; -----------------------------------------------------------------------------
global umath_align_down_32
umath_align_down_32:
    mov     rax, rdi
    and     rax, ~31
    ret

; -----------------------------------------------------------------------------
; umath_align_down_64 - round down to 64-byte boundary (ZMM / cache line)
; args:    rdi = val
; returns: rax = val & ~63
; -----------------------------------------------------------------------------
global umath_align_down_64
umath_align_down_64:
    mov     rax, rdi
    and     rax, ~63
    ret

; -----------------------------------------------------------------------------
; umath_align_down_generic - round val down to multiple of align (any align>=1)
; args:    rdi = val
;          rsi = align (>= 1; align==0 returns val unchanged)
; returns: rax = floor(val / align) * align
; -----------------------------------------------------------------------------
global umath_align_down_generic
umath_align_down_generic:
    test    rsi, rsi
    jz      .passthrough
    mov     rax, rdi
    xor     rdx, rdx
    div     rsi
    imul    rax, rsi
    ret
.passthrough:
    mov     rax, rdi
    ret

; -----------------------------------------------------------------------------
; umath_is_aligned32 - check if val is aligned to `align` (power of 2)
; args:    edi = val, esi = align (power of 2)
; returns: eax = 1 if (val mod align) == 0, 0 otherwise
; -----------------------------------------------------------------------------
global umath_is_aligned32
umath_is_aligned32:
    mov     eax, edi
    mov     ecx, esi
    dec     ecx
    and     eax, ecx
    test    eax, eax
    setz    al
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_is_aligned64 - check if val is aligned to `align` (power of 2)
; args:    rdi = val, rsi = align (power of 2)
; returns: eax = 1 if (val mod align) == 0, 0 otherwise
; -----------------------------------------------------------------------------
global umath_is_aligned64
umath_is_aligned64:
    mov     rax, rdi
    mov     rcx, rsi
    dec     rcx
    and     rax, rcx
    test    rax, rax
    setz    al
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_is_aligned_ptr - check if pointer is aligned to `align` (power of 2)
; args:    rdi = pointer, rsi = align (power of 2)
; returns: eax = 1 if aligned, 0 otherwise
; -----------------------------------------------------------------------------
global umath_is_aligned_ptr
umath_is_aligned_ptr:
    mov     rax, rdi
    mov     rcx, rsi
    dec     rcx
    and     rax, rcx
    test    rax, rax
    setz    al
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_offset_in_block32 - offset of val within its alignment block
; args:    edi = val, esi = align (power of 2)
; returns: eax = val mod align (= val & (align-1))
; -----------------------------------------------------------------------------
global umath_offset_in_block32
umath_offset_in_block32:
    mov     eax, edi
    mov     ecx, esi
    dec     ecx
    and     eax, ecx
    ret

; -----------------------------------------------------------------------------
; umath_offset_in_block64 - offset of val within its alignment block
; args:    rdi = val, rsi = align (power of 2)
; returns: rax = val mod align (= val & (align-1))
; -----------------------------------------------------------------------------
global umath_offset_in_block64
umath_offset_in_block64:
    mov     rax, rdi
    mov     rcx, rsi
    dec     rcx
    and     rax, rcx
    ret
%endif ; GUARD_LIB_UMATH_BITS_ALIGN_DOWN_ASM
