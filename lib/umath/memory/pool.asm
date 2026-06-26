; =============================================================================
; umath - unified math library
; memory/pool.asm - robust object pool allocator implementation
; =============================================================================
; Layout of the Pool structure:
;
;   +-------------------+-------------------+-------------------+-------------------+
;   | start (8 bytes)   | free_list (8 B)   | obj_size | tot_objs| free_cnt | pad   |
;   +-------------------+-------------------+-------------------+-------------------+
;   Offset 0            Offset 8            Offset 16 Offset 20 Offset 24
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
POOL_MAGIC equ 0x554D415454504F4C      ; ASCII "UMATTPOL" (Umath Pool)

; -----------------------------------------------------------------------------
; umath_pool_init - initialize an object pool
; args:    rdi = pointer to UmathPool struct
;          rsi = pointer to buffer to use
;          rdx = size of buffer in bytes
;          rcx = size of each object in bytes (will be aligned to >=8)
; returns: rax = 1 (success) or 0 (failure/invalid inputs)
; -----------------------------------------------------------------------------
global umath_pool_init
umath_pool_init:
    xor     rax, rax
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done
    test    rdx, rdx
    jz      .done
    test    rcx, rcx
    jz      .done

    ; enforce minimum size of 8 and align object_size to 8
    cmp     rcx, 8
    jae     .align_obj
    mov     rcx, 8
.align_obj:
    add     rcx, 7
    and     rcx, ~7             ; round up to nearest multiple of 8

    ; calculate total objects
    mov     rax, rdx            ; rax = buffer size
    xor     rdx, rdx
    div     rcx                 ; rax = buffer size / object size
    test    rax, rax
    jz      .empty_pool

    ; write struct fields
    mov     [rdi + 0], rsi      ; start = buf
    mov     [rdi + 16], ecx     ; object_size
    mov     [rdi + 20], eax     ; total_objects
    mov     [rdi + 24], eax     ; free_count

    mov     r8, POOL_MAGIC
    mov     [rdi + 32], r8      ; magic = POOL_MAGIC

    ; build the linked free-list
    mov     r8, rsi             ; r8 = current block pointer
    mov     r9, rax             ; r9 = loop counter
    dec     r9                  ; total_objects - 1 times
    jz      .last_block

.loop_format:
    mov     r10, r8
    add     r10, rcx            ; next = current + object_size
    mov     [r8], r10           ; *current = next
    mov     r8, r10             ; current = next
    dec     r9
    jnz     .loop_format

.last_block:
    mov     qword [r8], 0       ; last block next = NULL
    mov     [rdi + 8], rsi      ; free_list = buf
    mov     rax, 1
    ret

.empty_pool:
    mov     qword [rdi + 0], 0
    mov     qword [rdi + 8], 0
    mov     dword [rdi + 16], 0
    mov     dword [rdi + 20], 0
    mov     dword [rdi + 24], 0
    mov     qword [rdi + 32], 0
.done:
    ret

; -----------------------------------------------------------------------------
; umath_pool_alloc - allocate an object slot from the pool
; args:    rdi = pointer to UmathPool struct
; returns: rax = pointer to allocated slot, or 0 (NULL) if empty
; -----------------------------------------------------------------------------
global umath_pool_alloc
umath_pool_alloc:
    xor     rax, rax
    test    rdi, rdi
    jz      .done

    mov     r8, [rdi + 32]
    cmp     r8, POOL_MAGIC
    jne     .done

    mov     rax, [rdi + 8]      ; rax = free_list
    test    rax, rax
    jz      .done               ; pool empty

    ; pop block
    mov     rcx, [rax]          ; rcx = next free slot
    mov     [rdi + 8], rcx      ; free_list = next
    
    ; decrement free count
    dec     dword [rdi + 24]
.done:
    ret

; -----------------------------------------------------------------------------
; umath_pool_alloc_zeroed - allocate a slot and zero-initialize it
; args:    rdi = pointer to UmathPool struct
; returns: rax = pointer to zeroed slot, or 0 (NULL) if empty
; -----------------------------------------------------------------------------
global umath_pool_alloc_zeroed
umath_pool_alloc_zeroed:
    push    rbx
    push    r12

    mov     rbx, rdi            ; rbx = pool
    call    umath_pool_alloc    ; rax = slot
    test    rax, rax
    jz      .done_zero

    mov     r12, rax
    mov     ecx, [rbx + 16]     ; rcx = object_size
    
    ; zero block
    mov     rdi, rax
    xor     eax, eax
    rep     stosb
    
    mov     rax, r12

.done_zero:
    pop     r12
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; umath_pool_free - release an object slot back to the pool
; args:    rdi = pointer to UmathPool struct
;          rsi = pointer to slot to free
; returns: rax = 1 (success) or 0 (failure/invalid pointer)
; -----------------------------------------------------------------------------
global umath_pool_free
umath_pool_free:
    xor     rax, rax
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done

    mov     r8, [rdi + 32]
    cmp     r8, POOL_MAGIC
    jne     .done

    ; validate slot pointer range and alignment
    push    rdi
    push    rsi
    call    umath_pool_contains
    pop     rsi
    pop     rdi
    test    rax, rax
    jz      .done

    ; push slot to free_list
    mov     rcx, [rdi + 8]      ; old free_list
    mov     [rsi], rcx          ; *slot = old free_list
    mov     [rdi + 8], rsi      ; free_list = slot

    ; increment free count
    inc     dword [rdi + 24]
    mov     rax, 1
.done:
    ret

; -----------------------------------------------------------------------------
; umath_pool_contains - check if pointer belongs to and is aligned with this pool
; args:    rdi = pointer to UmathPool struct
;          rsi = pointer to check
; returns: rax = 1 (yes) or 0 (no/invalid)
; -----------------------------------------------------------------------------
global umath_pool_contains
umath_pool_contains:
    xor     rax, rax
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done

    mov     r8, [rdi + 32]
    cmp     r8, POOL_MAGIC
    jne     .done

    mov     r8, [rdi + 0]       ; start
    mov     ecx, [rdi + 16]     ; object_size
    mov     r9d, [rdi + 20]     ; total_objects

    ; boundary check: rsi >= start and rsi < start + total_objects * object_size
    cmp     rsi, r8
    jb      .done
    
    mov     rax, rcx
    mul     r9
    test    rdx, rdx
    jnz     .done               ; overflow safety check
    
    add     rax, r8             ; limit
    cmp     rsi, rax
    jae     .done

    ; check alignment
    mov     rax, rsi
    sub     rax, r8             ; offset
    xor     rdx, rdx
    div     rcx                 ; offset % object_size
    test    rdx, rdx
    jnz     .done               ; unaligned, invalid pointer!

    mov     rax, 1
.done:
    ret

; -----------------------------------------------------------------------------
; umath_pool_clear - clear all pool allocations (re-initializes free list)
; args:    rdi = pointer to UmathPool struct
; returns: void
; -----------------------------------------------------------------------------
global umath_pool_clear
umath_pool_clear:
    test    rdi, rdi
    jz      .done

    mov     rax, [rdi + 32]
    cmp     rax, POOL_MAGIC
    jne     .done

    mov     rsi, [rdi + 0]      ; start (buf)
    mov     ecx, [rdi + 16]     ; object_size
    mov     eax, [rdi + 20]     ; total_objects
    test    rax, rax
    jz      .done               ; empty pool

    mov     [rdi + 24], eax     ; free_count = total_objects

    ; rebuild the free-list
    mov     r8, rsi             ; current = start
    mov     r9, rax             ; total_objects
    dec     r9
    jz      .last_block

.loop_format:
    mov     r10, r8
    add     r10, rcx
    mov     [r8], r10
    mov     r8, r10
    dec     r9
    jnz     .loop_format

.last_block:
    mov     qword [r8], 0
    mov     [rdi + 8], rsi
.done:
    ret

; -----------------------------------------------------------------------------
; umath_pool_verify - verify integrity of the pool structures and free list links
; args:    rdi = pointer to UmathPool struct
; returns: rax = 1 (integrity matches) or 0 (corruption detected)
; -----------------------------------------------------------------------------
global umath_pool_verify
umath_pool_verify:
    xor     rax, rax
    test    rdi, rdi
    jz      .corrupted

    mov     rcx, [rdi + 32]     ; magic
    cmp     rcx, POOL_MAGIC
    jne     .corrupted

    mov     r8, [rdi + 0]       ; start
    mov     r9d, [rdi + 20]     ; total_objects
    mov     r10d, [rdi + 16]    ; object_size

    ; limit = start + total_objects * object_size
    mov     rax, r10
    mul     r9
    add     rax, r8             ; limit

    ; walk list and count nodes to prevent loops and catch corruption
    mov     rsi, [rdi + 8]      ; current = free_list
    xor     rcx, rcx            ; count = 0

.walk_loop:
    test    rsi, rsi
    jz      .walk_ok
    
    ; check bounds
    cmp     rsi, r8
    jb      .corrupted
    cmp     rsi, rax
    jae     .corrupted

    ; check alignment
    push    rax
    mov     rax, rsi
    sub     rax, r8
    xor     rdx, rdx
    div     r10
    mov     r11, rdx
    pop     rax
    test    r11, r11
    jnz     .corrupted          ; unaligned slot in list!

    inc     rcx
    cmp     rcx, r9
    ja      .corrupted          ; cycle detected (loop exceeds max objects)

    mov     rsi, [rsi]          ; walk to next
    jmp     .walk_loop

.walk_ok:
    ; check count matches free_count
    mov     edx, [rdi + 24]     ; free_count
    cmp     ecx, edx
    jne     .corrupted          ; block count mismatch

    mov     rax, 1
    ret

.corrupted:
    xor     rax, rax
    ret
