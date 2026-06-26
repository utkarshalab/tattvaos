; =============================================================================
; umath - unified math library
; memory/region.asm - robust hierarchical region (scoped) allocator
; =============================================================================
; Layout of the Region structure:
;
;   +-------------------+-------------------+-------------------+-------------------+
;   | parent (8 bytes)  | start (8 bytes)   | current (8 bytes) | end (8 bytes)     |
;   +-------------------+-------------------+-------------------+-------------------+
;   Offset 0            Offset 8            Offset 16           Offset 24
;
;   +-------------------+
;   | magic (8 bytes)   |
;   +-------------------+
;   Offset 32
;
; Targets 64-bit AMD64 System V ABI calling conventions.
; =============================================================================

bits 64
section .text

; Constants
REGION_MAGIC equ 0x554D41545452474E     ; ASCII "UMATTRGN" (Umath Region)

; -----------------------------------------------------------------------------
; umath_region_init - initialize a region allocator
; args:    rdi = pointer to UmathRegion struct
;          rsi = pointer to backing buffer to use
;          rdx = size of backing buffer in bytes
;          rcx = pointer to parent UmathRegion struct (can be NULL)
; returns: rax = 1 (success) or 0 (failure)
; -----------------------------------------------------------------------------
global umath_region_init
umath_region_init:
    xor     rax, rax
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done
    test    rdx, rdx
    jz      .done

    mov     [rdi + 0], rcx      ; region->parent = parent_region
    mov     [rdi + 8], rsi      ; region->start = buf
    mov     [rdi + 16], rsi     ; region->current = buf
    
    add     rsi, rdx
    jc      .done               ; overflow check
    mov     [rdi + 24], rsi     ; region->end = buf + size

    mov     r8, REGION_MAGIC
    mov     [rdi + 32], r8      ; region->magic = REGION_MAGIC
    mov     rax, 1
.done:
    ret

; -----------------------------------------------------------------------------
; umath_region_alloc - allocate aligned memory from the region
; args:    rdi = pointer to UmathRegion struct
;          rsi = size in bytes
;          rdx = alignment boundary (must be power of 2, default 8 if 0)
; returns: rax = allocated pointer, or 0 (NULL) if out of memory
; -----------------------------------------------------------------------------
global umath_region_alloc
umath_region_alloc:
    xor     rax, rax
    test    rdi, rdi
    jz      .fail
    test    rsi, rsi
    jz      .fail

    ; verify magic number
    mov     r8, [rdi + 32]      ; magic
    cmp     r8, REGION_MAGIC
    jne     .fail

    mov     rcx, [rdi + 16]     ; rcx = current
    mov     r8, [rdi + 24]      ; r8 = end

    ; default alignment to 8
    test    rdx, rdx
    jnz     .check_pow2
    mov     rdx, 8
.check_pow2:
    ; validate alignment power-of-2
    mov     r9, rdx
    dec     r9
    test    r9, rdx
    jnz     .fail

    ; align pointer up: (current + align - 1) & ~(align - 1)
    add     rcx, r9             ; rcx = current + align - 1
    jc      .fail               ; overflow check
    not     r9
    and     rcx, r9             ; rcx = aligned pointer

    ; boundary check
    mov     rax, rcx
    add     rax, rsi            ; rax = new_current
    jc      .fail
    cmp     rax, r8
    ja      .fail               ; out of memory

    ; update current and return aligned pointer
    mov     [rdi + 16], rax
    mov     rax, rcx
    ret

.fail:
    xor     rax, rax
    ret

; -----------------------------------------------------------------------------
; umath_region_alloc_zeroed - allocate aligned memory and zero-initialize it
; args:    rdi = pointer to UmathRegion struct
;          rsi = size in bytes
;          rdx = alignment boundary
; returns: rax = allocated pointer, or 0 (NULL) if out of memory
; -----------------------------------------------------------------------------
global umath_region_alloc_zeroed
umath_region_alloc_zeroed:
    push    rbx
    push    r12

    mov     rbx, rdi            ; rbx = region
    mov     r12, rsi            ; r12 = size
    call    umath_region_alloc  ; rax = allocated pointer
    test    rax, rax
    jz      .done_zero

    ; zero block
    mov     rdi, rax
    mov     rcx, r12
    xor     eax, eax
    mov     r12, rdi            ; preserve ptr
    rep     stosb
    mov     rax, r12

.done_zero:
    pop     r12
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; umath_region_free_all - reset all allocations in this region (scoped reset)
; args:    rdi = pointer to UmathRegion struct
;          rsi = clean_memory flag (if 1, zeroes out the allocated memory region)
; returns: void
; -----------------------------------------------------------------------------
global umath_region_free_all
umath_region_free_all:
    test    rdi, rdi
    jz      .done

    mov     rcx, [rdi + 32]
    cmp     rcx, REGION_MAGIC
    jne     .done

    mov     rax, [rdi + 8]      ; start
    mov     rdx, [rdi + 16]     ; current

    test    rsi, rsi
    jz      .perform_reset

    cmp     rax, rdx
    jae     .perform_reset

    ; zero out memory range
    mov     rcx, rdx
    sub     rcx, rax            ; size
    push    rdi
    mov     rdi, rax
    xor     eax, eax
    rep     stosb
    pop     rdi

.perform_reset:
    mov     rax, [rdi + 8]
    mov     [rdi + 16], rax     ; current = start
.done:
    ret

; -----------------------------------------------------------------------------
; umath_region_create_child - allocate and initialize child region from parent
; args:    rdi = pointer to parent UmathRegion struct
;          rsi = pointer to child UmathRegion struct (to be initialized)
;          rdx = size of child region buffer in bytes
; returns: rax = pointer to child UmathRegion struct on success, 0 (NULL) on failure
; -----------------------------------------------------------------------------
global umath_region_create_child
umath_region_create_child:
    push    rbx
    push    r12
    push    r13

    mov     rbx, rdi            ; rbx = parent
    mov     r12, rsi            ; r12 = child_struct
    mov     r13, rdx            ; r13 = child_size

    ; verify parent magic
    mov     rax, [rbx + 32]
    cmp     rax, REGION_MAGIC
    jne     .fail

    ; allocate child_size from parent region, aligned to 16 bytes
    mov     rdi, rbx            ; arg0 = parent
    mov     rsi, r13            ; arg1 = child_size
    mov     rdx, 16             ; arg2 = alignment
    call    umath_region_alloc  ; rax = child_buf

    test    rax, rax
    jz      .fail               ; parent region out of memory

    ; initialize child region
    mov     rdi, r12            ; child_struct
    mov     rsi, rax            ; child_buf
    mov     rdx, r13            ; child_size
    mov     rcx, rbx            ; parent = parent
    call    umath_region_init

    mov     rax, r12            ; return child region struct
    jmp     .done

.fail:
    xor     rax, rax
.done:
    pop     r13
    pop     r12
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; umath_region_is_descendant - check if child is a descendant of ancestor
; args:    rdi = pointer to child UmathRegion
;          rsi = pointer to potential ancestor UmathRegion
; returns: rax = 1 (yes, child is descendant) or 0 (no)
; -----------------------------------------------------------------------------
global umath_region_is_descendant
umath_region_is_descendant:
    xor     rax, rax
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done

.walk_parent:
    mov     rdi, [rdi + 0]      ; child = child->parent
    test    rdi, rdi
    jz      .done               ; reached top-level without finding ancestor

    cmp     rdi, rsi
    je      .found

    ; verify child magic to prevent infinite loop on corrupted parent links
    mov     rcx, [rdi + 32]
    cmp     rcx, REGION_MAGIC
    jne     .done               ; corrupted parent link, abort search

    jmp     .walk_parent

.found:
    mov     rax, 1
.done:
    ret

; -----------------------------------------------------------------------------
; umath_region_contains - check if a pointer falls within this region's buffer
; args:    rdi = pointer to UmathRegion struct
;          rsi = pointer to check
;          rdx = check_ancestors flag (if 1, also checks parent regions recursively)
; returns: rax = 1 (yes) or 0 (no)
; -----------------------------------------------------------------------------
global umath_region_contains
umath_region_contains:
    xor     rax, rax
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done

.check_loop:
    ; verify magic number
    mov     rcx, [rdi + 32]
    cmp     rcx, REGION_MAGIC
    jne     .done

    mov     rcx, [rdi + 8]      ; start
    mov     r8, [rdi + 24]      ; end

    cmp     rsi, rcx
    jb      .next_ancestor
    cmp     rsi, r8
    jb      .found

.next_ancestor:
    test    rdx, rdx
    jz      .done               ; check_ancestors is 0, do not walk up
    
    mov     rdi, [rdi + 0]      ; parent
    test    rdi, rdi
    jnz     .check_loop
    jmp     .done

.found:
    mov     rax, 1
.done:
    ret

; -----------------------------------------------------------------------------
; umath_region_verify - verify integrity of the region structure and pointers
; args:    rdi = pointer to UmathRegion struct
; returns: rax = 1 (struct is consistent/valid) or 0 (corrupted or invalid)
; -----------------------------------------------------------------------------
global umath_region_verify
umath_region_verify:
    xor     rax, rax
    test    rdi, rdi
    jz      .invalid

    ; check magic
    mov     rcx, [rdi + 32]     ; magic
    cmp     rcx, REGION_MAGIC
    jne     .invalid

    ; read pointers
    mov     rdx, [rdi + 8]      ; start
    mov     rsi, [rdi + 16]     ; current
    mov     r8, [rdi + 24]      ; end

    ; verify invariant: start <= current <= end
    cmp     rdx, rsi
    ja      .invalid
    cmp     rsi, r8
    ja      .invalid
    cmp     rdx, r8
    jae     .invalid

    mov     rax, 1
    ret

.invalid:
    xor     rax, rax
    ret

; -----------------------------------------------------------------------------
; umath_region_available - get remaining capacity of the region
; args:    rdi = pointer to UmathRegion struct
; returns: rax = remaining space in bytes
; -----------------------------------------------------------------------------
global umath_region_available
umath_region_available:
    xor     rax, rax
    test    rdi, rdi
    jz      .done

    mov     rcx, [rdi + 32]
    cmp     rcx, REGION_MAGIC
    jne     .done

    mov     rax, [rdi + 24]     ; end
    sub     rax, [rdi + 16]     ; end - current
.done:
    ret
