; =============================================================================
; umath - unified math library
; memory/align.asm - robust pointer and memory alignment arithmetic
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; Alignment math helper details:
;   - Power-of-2 alignments use fast bitwise masking.
;   - Non-power-of-2 alignments fall back to integer division and multiplication.
;   - Robust overflow safety checks on all address adjustments.
; =============================================================================

bits 64
section .text

; -----------------------------------------------------------------------------
; umath_mem_align - align pointer up to nearest boundary
; args:    rdi = input address / pointer
;          rsi = alignment boundary (can be power-of-2 or arbitrary positive integer)
; returns: rax = aligned pointer, or 0 on overflow or invalid arguments
; -----------------------------------------------------------------------------
global umath_mem_align
umath_mem_align:
    mov     rax, rdi
    test    rsi, rsi
    jz      .err_align          ; alignment cannot be 0
    cmp     rsi, 1
    jbe     .done               ; alignment <= 1 -> no-op

    ; check if alignment is a power of 2: (rsi & (rsi - 1)) == 0
    mov     rcx, rsi
    dec     rcx
    test    rcx, rsi
    jnz     .generic_align      ; not power-of-2, use division

    ; power-of-2 alignment: (rax + align - 1) & ~(align - 1)
    add     rax, rcx
    jc      .err_align          ; overflow check
    not     rcx
    and     rax, rcx
    ret

.generic_align:
    ; non-power-of-2 alignment: ((rax + align - 1) / align) * align
    mov     rcx, rsi            ; divisor
    add     rax, rcx
    dec     rax                 ; rax = rax + align - 1
    jc      .err_align          ; overflow check
    
    xor     rdx, rdx
    div     rcx                 ; rax = rax / align
    mul     rcx                 ; rax = rax * align (rdx:rax)
    test    rdx, rdx
    jnz     .err_align          ; multiplication overflowed 64 bits
.done:
    ret

.err_align:
    xor     rax, rax
    ret

; -----------------------------------------------------------------------------
; umath_mem_is_aligned - check if pointer is aligned to given boundary
; args:    rdi = pointer / address
;          rsi = alignment boundary
; returns: rax = 1 (aligned) or 0 (unaligned)
; -----------------------------------------------------------------------------
global umath_mem_is_aligned
umath_mem_is_aligned:
    mov     rax, 1
    test    rsi, rsi
    jz      .unaligned          ; alignment of 0 is invalid
    cmp     rsi, 1
    jbe     .done               ; alignment <= 1 -> always aligned

    ; check power-of-2
    mov     rcx, rsi
    dec     rcx
    test    rcx, rsi
    jnz     .generic_check

    ; power-of-2 check: (rdi & (align - 1)) == 0
    test    rdi, rcx
    setz    al
    movzx   rax, al
    ret

.generic_check:
    mov     rax, rdi
    xor     rdx, rdx
    div     rsi                 ; rdx = rdi % align
    test    rdx, rdx
    setz    al
    movzx   rax, al
.done:
    ret

.unaligned:
    xor     rax, rax
    ret

; -----------------------------------------------------------------------------
; umath_mem_align_offset - align address with an offset (e.g. for header prepending)
;                          finds the smallest address 'a' >= rdi such that:
;                          (a + rdx) % rsi == 0
; args:    rdi = input address
;          rsi = alignment boundary (must be power of 2)
;          rdx = offset value in bytes
; returns: rax = aligned address, or 0 on overflow/error
; -----------------------------------------------------------------------------
global umath_mem_align_offset
umath_mem_align_offset:
    xor     rax, rax
    test    rsi, rsi
    jz      .err_offset
    
    ; check alignment is power of 2
    mov     rcx, rsi
    dec     rcx
    test    rcx, rsi
    jnz     .err_offset         ; must be power of 2

    ; check if offset is larger than alignment, wrap it modulo alignment
    mov     r8, rdx
    and     r8, rcx             ; r8 = offset % alignment

    ; we need: (aligned + offset) % align == 0
    ; let payload = rdi + offset
    ; aligned_payload = (payload + align - 1) & ~(align - 1)
    ; aligned_addr = aligned_payload - offset
    mov     rax, rdi
    add     rax, r8             ; rax = rdi + wrapped_offset
    jc      .err_offset

    add     rax, rcx            ; payload + align - 1
    jc      .err_offset
    not     rcx
    and     rax, rcx            ; rax = aligned_payload

    ; subtract offset
    sub     rax, r8             ; rax = aligned_addr
    
    ; sanity check: must be >= original address
    cmp     rax, rdi
    jae     .done_offset
    
    ; if subtraction wrapped below original, add alignment
    add     rax, rsi
    jc      .err_offset

.done_offset:
    ret

.err_offset:
    xor     rax, rax
    ret

; -----------------------------------------------------------------------------
; umath_mem_align_page - align pointer up to 4KB page boundary
; args:    rdi = pointer
; returns: rax = aligned pointer, or 0 on overflow
; -----------------------------------------------------------------------------
global umath_mem_align_page
umath_mem_align_page:
    mov     rax, rdi
    add     rax, 4095
    jc      .err_page
    and     rax, ~4095
    ret
.err_page:
    xor     rax, rax
    ret

; -----------------------------------------------------------------------------
; umath_mem_is_page_aligned - check if pointer is page-aligned
; args:    rdi = pointer
; returns: rax = 1 (yes) or 0 (no)
; -----------------------------------------------------------------------------
global umath_mem_is_page_aligned
umath_mem_is_page_aligned:
    test    rdi, 4095
    setz    al
    movzx   rax, al
    ret

; -----------------------------------------------------------------------------
; umath_mem_align_cacheline - align pointer up to 64-byte cache line boundary
; args:    rdi = pointer
; returns: rax = aligned pointer, or 0 on overflow
; -----------------------------------------------------------------------------
global umath_mem_align_cacheline
umath_mem_align_cacheline:
    mov     rax, rdi
    add     rax, 63
    jc      .err_cache
    and     rax, ~63
    ret
.err_cache:
    xor     rax, rax
    ret

; -----------------------------------------------------------------------------
; umath_mem_is_cacheline_aligned - check if pointer is cacheline-aligned
; args:    rdi = pointer
; returns: rax = 1 (yes) or 0 (no)
; -----------------------------------------------------------------------------
global umath_mem_is_cacheline_aligned
umath_mem_is_cacheline_aligned:
    test    rdi, 63
    setz    al
    movzx   rax, al
    ret

; -----------------------------------------------------------------------------
; umath_mem_align_block - compute aligned bounds of a memory block
; args:    rdi = input start of raw buffer
;          rsi = size of raw buffer in bytes
;          rdx = requested aligned payload size in bytes
;          rcx = alignment boundary
;          r8  = pointer to uint64_t to return actual offset padding at start
;          r9  = pointer to uint64_t to return actual padding at end
; returns: rax = aligned start address of the block, or 0 on failure/insufficient size
; -----------------------------------------------------------------------------
global umath_mem_align_block
umath_mem_align_block:
    xor     rax, rax
    test    rdi, rdi
    jz      .fail
    test    rsi, rsi
    jz      .fail
    test    rdx, rdx
    jz      .fail
    test    rcx, rcx
    jz      .fail

    ; preserve rbx
    push    rbx

    ; raw_end = start + raw_size
    mov     r10, rdi
    add     r10, rsi
    jc      .fail_pop

    ; aligned_start = align(raw_start, alignment)
    push    rdi
    push    rsi
    push    rdx
    push    rcx
    push    r8
    push    r9
    push    r10

    mov     rsi, rcx            ; alignment
    call    umath_mem_align     ; rax = aligned_start

    pop     r10
    pop     r9
    pop     r8
    pop     rcx
    pop     rdx
    pop     rsi
    pop     rdi

    test    rax, rax
    jz      .fail_pop

    ; check if aligned_start + payload_size <= raw_end
    mov     rbx, rax
    add     rbx, rdx            ; rbx = aligned_end
    jc      .fail_pop
    cmp     rbx, r10
    ja      .fail_pop           ; raw buffer is too small to fit aligned payload

    ; compute start padding = aligned_start - raw_start
    mov     rcx, rax
    sub     rcx, rdi            ; rcx = start padding
    test    r8, r8
    jz      .check_end_pad
    mov     [r8], rcx

.check_end_pad:
    ; compute end padding = raw_end - aligned_end
    mov     rcx, r10
    sub     rcx, rbx            ; rcx = end padding
    test    r9, r9
    jz      .done_block
    mov     [r9], rcx

.done_block:
    pop     rbx
    ret

.fail_pop:
    pop     rbx
.fail:
    xor     rax, rax
    ret
