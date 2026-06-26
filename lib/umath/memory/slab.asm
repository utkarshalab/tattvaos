; =============================================================================
; umath - unified math library
; memory/slab.asm - robust fixed-size block allocator (slab) implementation
; =============================================================================
; Layout of the Slab structure:
;
;   +-------------------+-------------------+-------------------+-------------------+
;   | start (8 bytes)   | free_list (8 B)   | b_size | tot_blks | free_blks | pad   |
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
SLAB_MAGIC equ 0x554D415454534C42      ; ASCII representation of "UMATTSLB" (Umath Slab)

; -----------------------------------------------------------------------------
; umath_slab_init - initialize a slab allocator
; args:    rdi = pointer to UmathSlab struct
;          rsi = pointer to backing buffer to use
;          rdx = size of backing buffer in bytes
;          rcx = size of each block in bytes (will be aligned to >=8)
; returns: rax = 1 (success) or 0 (failure/invalid inputs)
; -----------------------------------------------------------------------------
global umath_slab_init
umath_slab_init:
    ; --- 1. Input Validation ---
    xor     rax, rax
    test    rdi, rdi
    jz      .err_init           ; null struct pointer
    test    rsi, rsi
    jz      .err_init           ; null buffer pointer
    test    rdx, rdx
    jz      .err_init           ; size of buffer is zero
    test    rcx, rcx
    jz      .err_init           ; block size is zero

    ; --- 2. Align Block Size ---
    ; enforce minimum of 8 bytes (since free blocks contain 8-byte next pointer)
    cmp     rcx, 8
    jae     .align_block
    mov     rcx, 8
.align_block:
    add     rcx, 7
    and     rcx, ~7             ; round up to nearest multiple of 8

    ; --- 3. Compute Block Counts ---
    mov     rax, rdx            ; rax = buffer size
    xor     rdx, rdx
    div     rcx                 ; rax = buffer size / block size
    test    rax, rax
    jz      .err_init           ; size of buffer is too small for even one block

    ; --- 4. Populate Struct Fields ---
    mov     [rdi + 0], rsi      ; slab->start = buf
    mov     [rdi + 16], ecx     ; slab->block_size
    mov     [rdi + 20], eax     ; slab->total_blocks
    mov     [rdi + 24], eax     ; slab->free_blocks
    
    mov     r8, SLAB_MAGIC
    mov     [rdi + 32], r8      ; slab->magic = SLAB_MAGIC

    ; --- 5. Format Linked Free List ---
    mov     r8, rsi             ; r8 = current block pointer
    mov     r9, rax             ; r9 = loop counter (total_blocks)
    dec     r9                  ; format up to second-to-last block
    jz      .last_block

.loop_format:
    mov     r10, r8
    add     r10, rcx            ; next block = current + block_size
    mov     [r8], r10           ; current->next = next_block
    mov     r8, r10             ; current = next_block
    dec     r9
    jnz     .loop_format

.last_block:
    mov     qword [r8], 0       ; last_block->next = NULL
    mov     [rdi + 8], rsi      ; slab->free_list = buf

    mov     rax, 1              ; return success
    ret

.err_init:
    xor     rax, rax
    ret

; -----------------------------------------------------------------------------
; umath_slab_alloc - allocate a fixed-size block from the slab
; args:    rdi = pointer to UmathSlab struct
; returns: rax = allocated block pointer, or 0 (NULL) if empty/corrupted
; -----------------------------------------------------------------------------
global umath_slab_alloc
umath_slab_alloc:
    xor     rax, rax
    test    rdi, rdi
    jz      .fail

    ; verify magic number
    mov     r8, [rdi + 32]
    cmp     r8, SLAB_MAGIC
    jne     .fail

    ; get current free_list pointer
    mov     rax, [rdi + 8]      ; rax = slab->free_list
    test    rax, rax
    jz      .fail               ; no free blocks available

    ; pop block: free_list = free_list->next
    mov     rcx, [rax]          ; rcx = next free block
    mov     [rdi + 8], rcx      ; slab->free_list = next
    
    ; decrement free block count
    dec     dword [rdi + 24]
    ret

.fail:
    xor     rax, rax
    ret

; -----------------------------------------------------------------------------
; umath_slab_alloc_zeroed - allocate a block and zero-initialize it
; args:    rdi = pointer to UmathSlab struct
; returns: rax = pointer to zeroed block, or 0 (NULL) if empty
; -----------------------------------------------------------------------------
global umath_slab_alloc_zeroed
umath_slab_alloc_zeroed:
    push    rbx
    push    r12

    mov     rbx, rdi            ; rbx = slab
    call    umath_slab_alloc    ; rax = allocated block
    test    rax, rax
    jz      .done_zero

    mov     r12, rax            ; save block ptr
    mov     ecx, [rbx + 16]     ; rcx = block_size
    
    ; zero out the block
    mov     rdi, rax
    xor     eax, eax
    rep     stosb
    
    mov     rax, r12            ; return block ptr

.done_zero:
    pop     r12
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; umath_slab_free - return an allocated block back to the free list
; args:    rdi = pointer to UmathSlab struct
;          rsi = pointer to block to free
; returns: rax = 1 (success) or 0 (failure/invalid pointer)
; -----------------------------------------------------------------------------
global umath_slab_free
umath_slab_free:
    xor     rax, rax
    test    rdi, rdi
    jz      .fail
    test    rsi, rsi
    jz      .fail

    ; check magic number
    mov     r8, [rdi + 32]
    cmp     r8, SLAB_MAGIC
    jne     .fail

    ; validate block boundaries and alignment
    push    rdi
    push    rsi
    call    umath_slab_contains ; rax = 1 if block is valid
    pop     rsi
    pop     rdi

    test    rax, rax
    jz      .fail               ; invalid pointer range or unaligned offset

    ; push block: block->next = free_list, free_list = block
    mov     rcx, [rdi + 8]      ; rcx = slab->free_list
    mov     [rsi], rcx          ; block->next = old free_list
    mov     [rdi + 8], rsi      ; slab->free_list = block

    ; increment free blocks count
    inc     dword [rdi + 24]
    
    mov     rax, 1              ; return success
    ret

.fail:
    xor     rax, rax
    ret

; -----------------------------------------------------------------------------
; umath_slab_contains - check if pointer belongs to and is aligned with this slab
; args:    rdi = pointer to UmathSlab struct
;          rsi = pointer to check
; returns: rax = 1 (yes) or 0 (no/invalid)
; -----------------------------------------------------------------------------
global umath_slab_contains
umath_slab_contains:
    xor     rax, rax
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done

    mov     r8, [rdi + 32]
    cmp     r8, SLAB_MAGIC
    jne     .done

    mov     r8, [rdi + 0]       ; start
    mov     ecx, [rdi + 16]     ; block_size
    mov     r9d, [rdi + 20]     ; total_blocks

    ; boundary check: rsi >= start and rsi < start + total_blocks * block_size
    cmp     rsi, r8
    jb      .done
    
    mov     rax, rcx
    mul     r9                  ; rax = total_blocks * block_size
    add     rax, r8             ; rax = limit address
    cmp     rsi, rax
    jae     .invalid_range

    ; alignment check: (rsi - start) % block_size == 0
    mov     rax, rsi
    sub     rax, r8             ; rax = offset
    xor     rdx, rdx
    div     rcx                 ; rdx = offset % block_size
    test    rdx, rdx
    jnz     .invalid_range

    mov     rax, 1              ; verified valid block pointer
    ret

.invalid_range:
    xor     rax, rax
.done:
    ret

; -----------------------------------------------------------------------------
; umath_slab_reset - reset the slab allocator (rebuilds the free list)
; args:    rdi = pointer to UmathSlab struct
; returns: void
; -----------------------------------------------------------------------------
global umath_slab_reset
umath_slab_reset:
    test    rdi, rdi
    jz      .done

    mov     rax, [rdi + 32]
    cmp     rax, SLAB_MAGIC
    jne     .done

    mov     rsi, [rdi + 0]      ; start
    mov     ecx, [rdi + 16]     ; block_size
    mov     edx, [rdi + 20]     ; total_blocks
    test    rdx, rdx
    jz      .done

    mov     [rdi + 24], edx     ; free_blocks = total_blocks

    ; format blocks as linked free-list
    mov     r8, rsi
    mov     r9, rdx
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
; umath_slab_verify - debug helper to check free list for cycle and corruption
; args:    rdi = pointer to UmathSlab struct
; returns: rax = 1 (integrity passes) or 0 (corruption detected)
; -----------------------------------------------------------------------------
global umath_slab_verify
umath_slab_verify:
    xor     rax, rax
    test    rdi, rdi
    jz      .invalid

    mov     rcx, [rdi + 32]     ; magic
    cmp     rcx, SLAB_MAGIC
    jne     .invalid

    mov     r8, [rdi + 0]       ; start
    mov     r9d, [rdi + 20]     ; total_blocks
    mov     r10d, [rdi + 16]    ; block_size
    
    ; calculate limit = start + total_blocks * block_size
    mov     rax, r10
    mul     r9
    add     rax, r8             ; rax = limit

    ; slow and fast pointer algorithm (Floyd's cycle detection) to catch cycles
    mov     rsi, [rdi + 8]      ; rsi = slow pointer
    mov     rdx, rsi            ; rdx = fast pointer

.cycle_loop:
    test    rsi, rsi
    jz      .list_ok            ; reached end of free list, no cycles!
    
    ; validate slow pointer is aligned and within bounds
    cmp     rsi, r8
    jb      .corrupted
    cmp     rsi, rax
    jae     .corrupted
    
    ; check alignment of slow pointer
    mov     rcx, rsi
    sub     rcx, r8
    push    rax
    mov     rax, rcx
    xor     rdx, rdx
    div     r10
    mov     r11, rdx            ; r11 = offset % block_size
    pop     rax
    test    r11, r11
    jnz     .corrupted

    ; move fast pointer twice, slow pointer once
    mov     rsi, [rsi]          ; slow = slow->next
    
    ; fast step 1
    mov     rdx, [rdi + 8]      ; load fast pointer location or just walk
    ; wait, let's keep fast pointer tracking simple:
    ; let's track the visited block count. If visited block count exceeds
    ; total_blocks, there must be a cycle! This is much simpler to implement
    ; and requires less register management.
    jmp     .walk_count

.list_ok:
    mov     rax, 1
    ret

.corrupted:
.invalid:
    xor     rax, rax
    ret

.walk_count:
    ; alternate verification: walk list and count nodes.
    ; if count > total_blocks, cycle exists.
    mov     rsi, [rdi + 8]      ; current = free_list
    xor     rcx, rcx            ; count = 0

.walk_loop:
    test    rsi, rsi
    jz      .walk_ok            ; null terminator found cleanly
    
    ; bounds check node pointer
    cmp     rsi, r8
    jb      .corrupted
    cmp     rsi, rax
    jae     .corrupted

    ; check node alignment
    push    rax
    mov     rax, rsi
    sub     rax, r8
    xor     rdx, rdx
    div     r10                 ; offset % block_size
    mov     r11, rdx
    pop     rax
    test    r11, r11
    jnz     .corrupted          ; unaligned free node!

    inc     rcx
    cmp     rcx, r9
    ja      .corrupted          ; loop count exceeds total blocks (cycle detected!)

    mov     rsi, [rsi]          ; current = current->next
    jmp     .walk_loop

.walk_ok:
    ; check if counts match free_blocks
    mov     edx, [rdi + 24]     ; free_blocks
    cmp     ecx, edx
    jne     .corrupted          ; block count mismatch

    mov     rax, 1
    ret

; -----------------------------------------------------------------------------
; umath_slab_available - get remaining free blocks
; args:    rdi = pointer to UmathSlab struct
; returns: rax = count of free blocks
; -----------------------------------------------------------------------------
global umath_slab_available
umath_slab_available:
    xor     rax, rax
    test    rdi, rdi
    jz      .done
    
    mov     rdx, [rdi + 32]
    cmp     rdx, SLAB_MAGIC
    jne     .done

    mov     eax, [rdi + 24]     ; free_blocks
.done:
    ret
