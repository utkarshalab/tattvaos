%ifndef GUARD_LIB_UMATH_MEMORY_SPAN_ASM
%define GUARD_LIB_UMATH_MEMORY_SPAN_ASM
; =============================================================================
; umath - unified math library
; memory/span.asm - robust memory span/slice descriptor utilities
; =============================================================================
; Layout of the Span structure:
;
;   +-------------------+-------------------+
;   | ptr (8 bytes)     | size (8 bytes)    |
;   +-------------------+-------------------+
;   Offset 0            Offset 8
;
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; Design Principles:
;   - Bounds safety: Protects against buffer overflows, invalid offsets,
;     and wrap-around integer overflows on pointer logic.
;   - String/buffer compatibility: Implements lexicographical comparisons,
;     byte searching, and substring search (memmem) using spans.
; =============================================================================

bits 64
section .text

; -----------------------------------------------------------------------------
; umath_span_init - initialize a memory span descriptor
; args:    rdi = pointer to UmathSpan struct
;          rsi = backing pointer
;          rdx = size of span in bytes
; returns: rax = 1 (success) or 0 (failure/null pointers)
; -----------------------------------------------------------------------------
global umath_span_init
umath_span_init:
    xor     rax, rax
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done

    mov     [rdi + 0], rsi      ; span->ptr = ptr
    mov     [rdi + 8], rdx      ; span->size = size
    mov     rax, 1
.done:
    ret

; -----------------------------------------------------------------------------
; umath_span_subspan - create a safe sub-span view
; args:    rdi = pointer to input UmathSpan struct
;          rsi = offset within parent span
;          rdx = size of desired sub-span
;          rcx = pointer to output UmathSpan struct (to write result)
; returns: rax = 1 (success) or 0 (out of bounds or invalid arguments)
; -----------------------------------------------------------------------------
global umath_span_subspan
umath_span_subspan:
    xor     rax, rax
    test    rdi, rdi
    jz      .done
    test    rcx, rcx
    jz      .done

    mov     r8, [rdi + 0]       ; r8 = parent->ptr
    mov     r9, [rdi + 8]       ; r9 = parent->size

    ; boundary validation: offset + size <= parent->size
    mov     r10, rsi
    add     r10, rdx            ; r10 = offset + size
    jc      .done               ; overflow check
    cmp     r10, r9
    ja      .done               ; offset + size > parent->size

    ; create subspan: output->ptr = parent->ptr + offset, output->size = size
    add     r8, rsi
    mov     [rcx + 0], r8
    mov     [rcx + 8], rdx
    mov     rax, 1
.done:
    ret

; -----------------------------------------------------------------------------
; umath_span_split - split a span at a given offset into two sub-spans
; args:    rdi = pointer to parent UmathSpan struct
;          rsi = split offset
;          rdx = pointer to left UmathSpan struct
;          rcx = pointer to right UmathSpan struct
; returns: rax = 1 (success) or 0 (out of bounds)
; -----------------------------------------------------------------------------
global umath_span_split
umath_span_split:
    push    rbx
    xor     rax, rax
    test    rdi, rdi
    jz      .done_split
    test    rdx, rdx
    jz      .done_split
    test    rcx, rcx
    jz      .done_split

    mov     r8, [rdi + 0]       ; r8 = ptr
    mov     r9, [rdi + 8]       ; r9 = size

    ; validate split offset
    cmp     rsi, r9
    ja      .done_split         ; offset > size

    ; write left span: ptr = parent->ptr, size = offset
    mov     [rdx + 0], r8
    mov     [rdx + 8], rsi

    ; write right span: ptr = parent->ptr + offset, size = parent->size - offset
    mov     r10, r8
    add     r10, rsi            ; r10 = ptr + offset
    mov     r11, r9
    sub     r11, rsi            ; r11 = size - offset

    mov     [rcx + 0], r10
    mov     [rcx + 8], r11
    mov     rax, 1

.done_split:
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; umath_span_copy - copy contents between two spans up to min(dst.size, src.size)
; args:    rdi = pointer to destination UmathSpan
;          rsi = pointer to source UmathSpan
; returns: rax = actual count of bytes copied
; -----------------------------------------------------------------------------
global umath_span_copy
umath_span_copy:
    xor     rax, rax
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done

    mov     r8, [rdi + 0]       ; dst_ptr
    mov     r9, [rdi + 8]       ; dst_size
    mov     r10, [rsi + 0]      ; src_ptr
    mov     r11, [rsi + 8]      ; src_size

    test    r9, r9
    jz      .done
    test    r11, r11
    jz      .done

    ; determine copy count = min(dst_size, src_size)
    mov     rdx, r9
    cmp     rdx, r11
    jbe     .perform_copy
    mov     rdx, r11

.perform_copy:
    push    rdi
    push    rsi
    push    rdx                 ; preserve copy count

    mov     rdi, r8             ; arg0 = dst_ptr
    mov     rsi, r10            ; arg1 = src_ptr
    ; rdx is already = copy count (arg2)
    call    umath_memcpy        ; copy bytes

    pop     rax                 ; rax = copy count (return value)
    pop     rsi
    pop     rdi
.done:
    ret

; -----------------------------------------------------------------------------
; umath_span_compare - lexicographically compare two spans
; args:    rdi = pointer to UmathSpan a
;          rsi = pointer to UmathSpan b
; returns: rax = -1 (a < b), 0 (a == b), 1 (a > b)
; -----------------------------------------------------------------------------
global umath_span_compare
umath_span_compare:
    xor     rax, rax
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done

    mov     r8, [rdi + 0]       ; a_ptr
    mov     r9, [rdi + 8]       ; a_size
    mov     r10, [rsi + 0]      ; b_ptr
    mov     r11, [rsi + 8]      ; b_size

    ; compare up to min(a_size, b_size)
    mov     rdx, r9
    cmp     rdx, r11
    jbe     .do_cmp
    mov     rdx, r11

.do_cmp:
    test    rdx, rdx
    jz      .cmp_sizes          ; both sizes are 0 or one is 0

    push    r9
    push    r11
    mov     rdi, r8
    mov     rsi, r10
    ; rdx is already = min size
    call    umath_memcmp        ; compare bytes
    pop     r11
    pop     r9

    test    rax, rax
    jnz     .done               ; mismatch found, propagate -1/1

.cmp_sizes:
    ; if memory matches up to min size, compare span sizes
    cmp     r9, r11
    je      .equal
    jl      .less
    mov     rax, 1              ; a_size > b_size -> a > b
    ret
.less:
    mov     rax, -1             ; a_size < b_size -> a < b
    ret
.equal:
    xor     rax, rax
.done:
    ret

; -----------------------------------------------------------------------------
; umath_span_fill - fill span buffer with repeating byte
; args:    rdi = pointer to UmathSpan
;          rsi = byte value to fill
; returns: rax = 1 (success) or 0 (failure/null span)
; -----------------------------------------------------------------------------
global umath_span_fill
umath_span_fill:
    xor     rax, rax
    test    rdi, rdi
    jz      .done

    mov     r8, [rdi + 0]       ; ptr
    mov     r9, [rdi + 8]       ; size
    test    r9, r9
    jz      .done

    push    rdi
    mov     rdi, r8             ; destination
    ; rsi is already = byte val
    mov     rdx, r9             ; size
    call    umath_memset
    pop     rdi
    mov     rax, 1
.done:
    ret

; -----------------------------------------------------------------------------
; umath_span_find_byte - scan span for a byte value
; args:    rdi = pointer to UmathSpan
;          rsi = byte value to search for (low 8 bits)
; returns: rax = offset index of first occurrence, or -1 if not found
; -----------------------------------------------------------------------------
global umath_span_find_byte
umath_span_find_byte:
    mov     rax, -1
    test    rdi, rdi
    jz      .done

    mov     r8, [rdi + 0]       ; ptr
    mov     r9, [rdi + 8]       ; size
    test    r9, r9
    jz      .done

    ; scan using repne scasb
    mov     rdi, r8
    mov     al, sil             ; value to find
    mov     rcx, r9             ; scan count
    repne   scasb
    jne     .not_found          ; not found

    ; calculate index: rdi was incremented past match, so index = rdi - 1 - r8
    sub     rdi, r8
    dec     rdi
    mov     rax, rdi
    ret

.not_found:
    mov     rax, -1
.done:
    ret

; -----------------------------------------------------------------------------
; umath_span_find_subspan - search for occurrences of a pattern sub-span
;                           within a parent span (memmem)
; args:    rdi = pointer to parent UmathSpan
;          rsi = pointer to pattern UmathSpan
; returns: rax = offset index of first occurrence, or -1 if not found
; -----------------------------------------------------------------------------
global umath_span_find_subspan
umath_span_find_subspan:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    mov     rax, -1
    test    rdi, rdi
    jz      .done_search
    test    rsi, rsi
    jz      .done_search

    mov     rbx, [rdi + 0]      ; parent->ptr
    mov     r12, [rdi + 8]      ; parent->size
    mov     r13, [rsi + 0]      ; pattern->ptr
    mov     r14, [rsi + 8]      ; pattern->size

    test    r14, r14
    jz      .empty_pattern      ; empty pattern -> matches at offset 0
    cmp     r14, r12
    ja      .done_search        ; pattern is larger than parent -> no match

    ; search loop: loop offset from 0 to parent->size - pattern->size
    mov     r15, r12
    sub     r15, r14            ; r15 = max offset index

    xor     r9, r9              ; r9 = current offset index

.search_loop:
    ; compare bytes at current offset
    mov     rdi, rbx
    add     rdi, r9             ; rdi = parent_ptr + offset
    mov     rsi, r13            ; rsi = pattern_ptr
    mov     rdx, r14            ; rdx = pattern_size

    push    r9
    call    umath_memcmp        ; rax = cmp result
    pop     r9

    test    rax, rax
    jz      .found_match

    inc     r9
    cmp     r9, r15
    jbe     .search_loop

    mov     rax, -1             ; no match found
    jmp     .done_search

.found_match:
    mov     rax, r9             ; return offset index
    jmp     .done_search

.empty_pattern:
    xor     rax, rax            ; empty pattern matches at offset 0

.done_search:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

%endif ; GUARD_LIB_UMATH_MEMORY_SPAN_ASM
