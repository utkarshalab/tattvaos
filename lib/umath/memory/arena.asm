%ifndef GUARD_LIB_UMATH_MEMORY_ARENA_ASM
%define GUARD_LIB_UMATH_MEMORY_ARENA_ASM
; =============================================================================
; umath - unified math library
; memory/arena.asm - robust bump-allocator (arena) implementation
; =============================================================================
; Layout of the Arena structure:
;
;   +-------------------+-------------------+-------------------+-------------------+
;   | start (8 bytes)   | current (8 bytes) | end (8 bytes)     | magic (8 bytes)   |
;   +-------------------+-------------------+-------------------+-------------------+
;   Offset 0            Offset 8            Offset 16           Offset 24
;
; Design Principles:
;   - Robustness: Strict validation of all input arguments, pointers, and alignments.
;   - Security: Overflow checking on pointer additions, null checks, magic number guard.
;   - Performance: Hand-optimized instruction sequences, clean loop unrolling for zeroing.
;   - Standard ABI: Adherence to System V AMD64 ABI (rdi, rsi, rdx, rcx, r8, r9).
; =============================================================================

bits 64
section .text

; Constants
ARENA_MAGIC equ 0x554D41545441524E     ; ASCII representation of "UMATTARN" (Umath Arena)

; -----------------------------------------------------------------------------
; umath_arena_init - initialize an arena allocator
; args:    rdi = pointer to UmathArena struct
;          rsi = pointer to backing buffer to use
;          rdx = size of backing buffer in bytes
;          rcx = zero_on_init flag (if 1, zeroes out the entire buffer)
; returns: rax = 1 (success) or 0 (invalid inputs/null pointers)
; -----------------------------------------------------------------------------
global umath_arena_init
umath_arena_init:
    ; --- 1. Input Validation ---
    xor     rax, rax
    test    rdi, rdi
    jz      .err_init           ; arena struct pointer is null
    test    rsi, rsi
    jz      .err_init           ; backing buffer pointer is null
    test    rdx, rdx
    jz      .err_init           ; backing buffer size is zero

    ; --- 2. Write Struct Fields ---
    mov     [rdi + 0], rsi      ; arena->start = buf
    mov     [rdi + 8], rsi      ; arena->current = buf
    
    ; calculate end address = buf + size
    mov     r8, rsi
    add     r8, rdx             ; r8 = buf + size
    jc      .err_init           ; overflow check on address calculation
    mov     [rdi + 16], r8      ; arena->end = buf + size

    ; set magic number for integrity validation
    mov     r9, ARENA_MAGIC
    mov     [rdi + 24], r9      ; arena->magic = ARENA_MAGIC

    ; --- 3. Zero Out backing buffer if flag is set ---
    test    rcx, rcx
    jz      .success

    ; zeroing backing buffer: rsi = start, rdx = size
    mov     rcx, rdx
    mov     rdi, rsi            ; destination = buffer start
    xor     eax, eax            ; fill value = 0

    ; use optimized rep stosb for clean zeroing
    rep     stosb

.success:
    mov     rax, 1
    ret

.err_init:
    xor     rax, rax
    ret

; -----------------------------------------------------------------------------
; umath_arena_alloc - allocate aligned memory from the arena
; args:    rdi = pointer to UmathArena struct
;          rsi = requested size in bytes
;          rdx = alignment boundary (must be power of 2: 1, 2, 4, 8, 16, 32, 64, etc.)
; returns: rax = allocated pointer, or 0 (NULL) if out of memory or invalid alignment
; -----------------------------------------------------------------------------
global umath_arena_alloc
umath_arena_alloc:
    ; --- 1. Input Validation ---
    xor     rax, rax
    test    rdi, rdi
    jz      .fail               ; null struct pointer
    test    rsi, rsi
    jz      .fail               ; size == 0 is invalid or returning null is safe

    ; verify magic number to ensure arena is initialized and uncorrupted
    mov     r8, [rdi + 24]      ; r8 = arena->magic
    mov     r9, ARENA_MAGIC
    cmp     r8, r9
    jne     .fail               ; invalid magic number

    ; --- 2. Alignment boundary validation ---
    ; Default alignment to 8 bytes if alignment argument is 0
    test    rdx, rdx
    jnz     .check_pow2
    mov     rdx, 8
.check_pow2:
    ; Validate that alignment is a power of 2: (align & (align - 1)) == 0
    mov     r8, rdx
    dec     r8                  ; r8 = align - 1
    test    r8, rdx
    jnz     .fail               ; alignment is not a power of two!

    ; --- 3. Compute Aligned Pointer ---
    mov     rcx, [rdi + 8]      ; rcx = arena->current
    mov     r10, [rdi + 16]     ; r10 = arena->end

    ; align pointer up: (current + align - 1) & ~(align - 1)
    add     rcx, r8             ; rcx = current + align - 1
    jc      .fail               ; overflow check
    not     r8                  ; r8 = ~(align - 1)
    and     rcx, r8             ; rcx = aligned pointer

    ; --- 4. Boundary check ---
    ; check if aligned_pointer + size <= end
    mov     rax, rcx
    add     rax, rsi            ; rax = new_current
    jc      .fail               ; overflow check
    cmp     rax, r10
    ja      .fail               ; aligned_pointer + size > end (out of memory)

    ; --- 5. Commit Allocation ---
    mov     [rdi + 8], rax      ; update arena->current = new_current
    mov     rax, rcx            ; return aligned pointer
    ret

.fail:
    xor     rax, rax
    ret

; -----------------------------------------------------------------------------
; umath_arena_alloc_zeroed - allocate aligned memory and zero-initialize it
; args:    rdi = pointer to UmathArena struct
;          rsi = requested size in bytes
;          rdx = alignment boundary
; returns: rax = allocated pointer, or 0 (NULL) if out of memory
; -----------------------------------------------------------------------------
global umath_arena_alloc_zeroed
umath_arena_alloc_zeroed:
    ; preserve registers across function call
    push    rbx
    push    r12
    push    r13

    mov     rbx, rdi            ; rbx = arena
    mov     r12, rsi            ; r12 = size
    mov     r13, rdx            ; r13 = alignment

    ; call allocator
    call    umath_arena_alloc   ; rax = allocated pointer

    test    rax, rax
    jz      .done_zero          ; allocation failed, propagate NULL

    ; zero out the allocated block
    mov     rdi, rax            ; destination address
    mov     rcx, r12            ; size of block
    xor     eax, eax            ; fill value = 0
    
    ; preserve returned pointer in r12
    mov     r12, rdi

    ; fast zeroing loop
    rep     stosb
    mov     rax, r12            ; restore allocated pointer

.done_zero:
    pop     r13
    pop     r12
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; umath_arena_realloc - reallocate/resize the most recent allocation in-place
; args:    rdi = pointer to UmathArena struct
;          rsi = original pointer returned by umath_arena_alloc
;          rdx = old size of block in bytes
;          rcx = new size of block in bytes
; returns: rax = resized pointer (same if expanded in-place, new if relocated, or NULL)
; -----------------------------------------------------------------------------
global umath_arena_realloc
umath_arena_realloc:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    mov     rbx, rdi            ; rbx = arena
    mov     r12, rsi            ; r12 = ptr
    mov     r13, rdx            ; r13 = old_size
    mov     r14, rcx            ; r14 = new_size

    ; verify arena magic number
    mov     rax, [rbx + 24]
    cmp     rax, ARENA_MAGIC
    jne     .realloc_fail

    ; verify pointer is in range of arena buffer
    mov     r8, [rbx + 0]       ; start
    mov     r9, [rbx + 8]       ; current
    cmp     r12, r8
    jb      .realloc_fail
    cmp     r12, r9
    jae     .realloc_fail

    ; check if this block is the top-most allocation
    ; i.e., ptr + old_size == current
    mov     rax, r12
    add     rax, r13            ; rax = ptr + old_size
    cmp     rax, r9
    jne     .realloc_relocate   ; not the most recent allocation, must relocate

    ; it is the most recent allocation, try in-place resize
    mov     r10, [rbx + 16]     ; r10 = end
    mov     r11, r12
    add     r11, r14            ; r11 = ptr + new_size
    jc      .realloc_fail
    cmp     r11, r10
    ja      .realloc_fail       ; new size exceeds arena boundary

    ; update current pointer in-place
    mov     [rbx + 8], r11
    mov     rax, r12            ; return same pointer
    jmp     .realloc_done

.realloc_relocate:
    ; allocate a new block
    mov     rdi, rbx            ; arg0 = arena
    mov     rsi, r14            ; arg1 = new_size
    mov     rdx, 8              ; arg2 = align to 8
    call    umath_arena_alloc   ; rax = new_ptr
    test    rax, rax
    jz      .realloc_fail       ; new allocation failed

    ; copy content from old block to new block
    mov     r15, rax            ; r15 = new_ptr
    mov     rdi, rax            ; dst = new_ptr
    mov     rsi, r12            ; src = old_ptr
    
    ; copy min(old_size, new_size) bytes
    mov     rcx, r13
    cmp     rcx, r14
    jbe     .do_copy
    mov     rcx, r14
.do_copy:
    rep     movsb
    mov     rax, r15            ; return new pointer
    jmp     .realloc_done

.realloc_fail:
    xor     rax, rax
.realloc_done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; umath_arena_reset - reset the arena (frees all allocations)
; args:    rdi = pointer to UmathArena struct
;          rsi = clean_memory flag (if 1, zeroes out the allocated memory)
; returns: void
; -----------------------------------------------------------------------------
global umath_arena_reset
umath_arena_reset:
    test    rdi, rdi
    jz      .done
    
    mov     r8, [rdi + 24]      ; magic
    cmp     r8, ARENA_MAGIC
    jne     .done

    mov     rax, [rdi + 0]      ; start
    mov     rdx, [rdi + 8]      ; current

    test    rsi, rsi
    jz      .perform_reset

    ; zero out memory between start and current
    cmp     rax, rdx
    jae     .perform_reset      ; nothing to zero (start >= current)

    mov     rcx, rdx
    sub     rcx, rax            ; size to zero
    push    rdi
    mov     rdi, rax            ; destination
    xor     eax, eax
    rep     stosb
    pop     rdi

.perform_reset:
    mov     rax, [rdi + 0]
    mov     [rdi + 8], rax      ; current = start
.done:
    ret

; -----------------------------------------------------------------------------
; umath_arena_mark - save a checkpoint of the current arena state
; args:    rdi = pointer to UmathArena struct
; returns: rax = checkpoint pointer, or 0 (NULL) if invalid arena
; -----------------------------------------------------------------------------
global umath_arena_mark
umath_arena_mark:
    xor     rax, rax
    test    rdi, rdi
    jz      .done
    mov     rdx, [rdi + 24]     ; magic
    cmp     rdx, ARENA_MAGIC
    jne     .done
    mov     rax, [rdi + 8]      ; current
.done:
    ret

; -----------------------------------------------------------------------------
; umath_arena_rewind - rewind the allocator to a previously marked checkpoint
; args:    rdi = pointer to UmathArena struct
;          rsi = checkpoint pointer
; returns: rax = 1 (success) or 0 (invalid checkpoint or uninitialized arena)
; -----------------------------------------------------------------------------
global umath_arena_rewind
umath_arena_rewind:
    xor     rax, rax
    test    rdi, rdi
    jz      .done
    
    mov     rcx, [rdi + 24]     ; magic
    cmp     rcx, ARENA_MAGIC
    jne     .done

    mov     rcx, [rdi + 0]      ; start
    mov     rdx, [rdi + 8]      ; current

    ; checkpoint validation: start <= checkpoint <= current
    cmp     rsi, rcx
    jb      .done
    cmp     rsi, rdx
    ja      .done

    mov     [rdi + 8], rsi      ; current = checkpoint
    mov     rax, 1
.done:
    ret

; -----------------------------------------------------------------------------
; umath_arena_verify - verify integrity of the arena structure and pointers
; args:    rdi = pointer to UmathArena struct
; returns: rax = 1 (struct is consistent/valid) or 0 (corrupted or invalid)
; -----------------------------------------------------------------------------
global umath_arena_verify
umath_arena_verify:
    xor     rax, rax
    test    rdi, rdi
    jz      .invalid            ; null struct

    ; check magic number
    mov     rcx, [rdi + 24]     ; magic
    cmp     rcx, ARENA_MAGIC
    jne     .invalid            ; magic mismatch

    ; read pointer variables
    mov     rdx, [rdi + 0]      ; start
    mov     rsi, [rdi + 8]      ; current
    mov     r8, [rdi + 16]      ; end

    ; verify invariant: start <= current <= end
    cmp     rdx, rsi
    ja      .invalid            ; start > current
    cmp     rsi, r8
    ja      .invalid            ; current > end

    ; verify end pointer is greater than start pointer (size > 0)
    cmp     rdx, r8
    jae     .invalid            ; start >= end

    mov     rax, 1              ; struct is valid
    ret

.invalid:
    xor     rax, rax
    ret

; -----------------------------------------------------------------------------
; umath_arena_available - get remaining capacity of the arena
; args:    rdi = pointer to UmathArena struct
; returns: rax = remaining space in bytes, or 0 if invalid struct
; -----------------------------------------------------------------------------
global umath_arena_available
umath_arena_available:
    xor     rax, rax
    test    rdi, rdi
    jz      .done
    
    mov     rdx, [rdi + 24]     ; magic
    cmp     rdx, ARENA_MAGIC
    jne     .done

    mov     rax, [rdi + 16]     ; end
    sub     rax, [rdi + 8]      ; end - current
.done:
    ret

%endif ; GUARD_LIB_UMATH_MEMORY_ARENA_ASM
