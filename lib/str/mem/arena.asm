; =============================================================================
; str/mem/arena.asm
; Arena (bump) allocator — fast, no individual free.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;
; -----------------------------------------------------------------------------
; Arena allocator:
;   - Backed by a contiguous memory region (caller-supplied or mmap'd)
;   - Allocate by bumping a pointer: O(1)
;   - No individual free — reset the entire arena at once
;   - Perfect for: per-request allocations, parse trees, temp buffers
;
; StrArena layout (40 bytes):
;   base    dq   — pointer to backing memory
;   ptr     dq   — current allocation pointer (bump cursor)
;   end     dq   — one past last byte of backing memory
;   align   dq   — default alignment (usually 8 or 16)
;   flags   dq   — arena flags
;
; Usage:
;   ; initialize from a static buffer
;   lea  rdi, [arena]
;   lea  rsi, [backing_buf]
;   mov  rdx, backing_buf_size
;   call str_arena_init
;
;   ; allocate 64 bytes
;   mov  rdi, arena
;   mov  rsi, 64
;   mov  rdx, 8       ; alignment
;   call str_arena_alloc
;   ; rax = pointer to 64 bytes, or null if OOM
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

; Arena struct offsets
struc StrArena
    .base   resq 1      ; backing memory start
    .ptr    resq 1      ; current bump cursor
    .end    resq 1      ; one past last byte
    .align  resq 1      ; default alignment
    .flags  resq 1      ; flags
endstruc

ARENA_SIZE      equ 40

; Arena flags
ARENA_FLAG_OWNS_MEM     equ 0x01    ; arena owns backing memory (mmap'd)
ARENA_FLAG_ZERO_ALLOC   equ 0x02    ; zero memory on alloc

section .text

; -----------------------------------------------------------------------------
; str_arena_init
;
; Initialize an arena from a caller-supplied backing buffer.
;
; Signature:
;   int64_t str_arena_init(StrArena *arena, uint8_t *buf, uint64_t buf_size)
;
; Arguments:
;   RDI  — pointer to StrArena struct (caller-allocated, ARENA_SIZE bytes)
;   RSI  — backing buffer pointer
;   RDX  — backing buffer size in bytes
;
; Returns:
;   RAX  = STR_OK
;   RAX  = STR_ERR_NULL   arena or buf is null
; -----------------------------------------------------------------------------

STR_FUNC str_arena_init

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    mov     [rdi + StrArena.base],  rsi
    mov     [rdi + StrArena.ptr],   rsi

    mov     rax, rsi
    add     rax, rdx
    mov     [rdi + StrArena.end],   rax

    mov     qword [rdi + StrArena.align], ALIGN_8
    mov     qword [rdi + StrArena.flags], 0

    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_arena_init

; -----------------------------------------------------------------------------
; str_arena_alloc
;
; Allocate size bytes from arena with given alignment.
;
; Signature:
;   void *str_arena_alloc(StrArena *arena, uint64_t size, uint64_t align)
;
; Arguments:
;   RDI  — arena pointer
;   RSI  — bytes to allocate
;   RDX  — alignment (must be power of 2, 0 = use arena default)
;
; Returns:
;   RAX  — pointer to allocated memory
;   RAX  = null (0) if out of memory
; -----------------------------------------------------------------------------

STR_FUNC str_arena_alloc

    test    rdi, rdi
    jz      .alloc_null

    ; use default alignment if rdx == 0
    test    rdx, rdx
    jnz     .alloc_have_align
    mov     rdx, [rdi + StrArena.align]

.alloc_have_align:
    ; align current ptr up to alignment
    ; aligned = (ptr + align - 1) & ~(align - 1)
    mov     rax, [rdi + StrArena.ptr]
    mov     rcx, rdx
    dec     rcx                 ; align - 1
    add     rax, rcx
    not     rcx
    and     rax, rcx            ; rax = aligned ptr

    ; check if allocation fits: aligned + size <= end
    mov     r8, rax
    add     r8, rsi
    jc      .alloc_oom          ; overflow

    cmp     r8, [rdi + StrArena.end]
    ja      .alloc_oom

    ; commit: update ptr
    mov     [rdi + StrArena.ptr], r8

    ; zero if flag set
    bt      qword [rdi + StrArena.flags], 1   ; ARENA_FLAG_ZERO_ALLOC
    jnc     .alloc_done

    push    rdi
    push    rsi
    mov     rdi, rax
    xor     esi, esi
    mov     ecx, esi
    mov     rcx, rsi
    rep stosb
    pop     rsi
    pop     rdi
    ; rax may be clobbered — recompute
    mov     rax, [rdi + StrArena.ptr]
    sub     rax, rsi

.alloc_done:
    pop     rbp
    ret

.alloc_null:
.alloc_oom:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_arena_alloc

; -----------------------------------------------------------------------------
; str_arena_alloc_zeroed
;
; Like str_arena_alloc but always zeroes the memory.
; -----------------------------------------------------------------------------

STR_FUNC str_arena_alloc_zeroed

    test    rdi, rdi
    jz      .az_null

    ; align ptr
    test    rdx, rdx
    jnz     .az_have_align
    mov     rdx, [rdi + StrArena.align]

.az_have_align:
    mov     rax, [rdi + StrArena.ptr]
    mov     rcx, rdx
    dec     rcx
    add     rax, rcx
    not     rcx
    and     rax, rcx

    mov     r8, rax
    add     r8, rsi
    jc      .az_oom

    cmp     r8, [rdi + StrArena.end]
    ja      .az_oom

    mov     [rdi + StrArena.ptr], r8

    ; zero the allocation
    push    rdi
    push    rsi
    push    rax

    mov     rdi, rax
    xor     eax, eax
    mov     rcx, rsi
    rep stosb

    pop     rax
    pop     rsi
    pop     rdi

    pop     rbp
    ret

.az_null:
.az_oom:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_arena_alloc_zeroed

; -----------------------------------------------------------------------------
; str_arena_reset
;
; Reset arena to empty — all previously allocated memory is reclaimed.
; Does NOT zero the backing memory.
;
; Signature:
;   int64_t str_arena_reset(StrArena *arena)
; -----------------------------------------------------------------------------

STR_FUNC str_arena_reset

    guard_null rdi, STR_ERR_NULL

    mov     rax, [rdi + StrArena.base]
    mov     [rdi + StrArena.ptr], rax

    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_arena_reset

; -----------------------------------------------------------------------------
; str_arena_used
;
; Return the number of bytes currently allocated from the arena.
;
; Signature:
;   uint64_t str_arena_used(const StrArena *arena)
; -----------------------------------------------------------------------------

STR_FUNC str_arena_used

    test    rdi, rdi
    jz      .au_zero

    mov     rax, [rdi + StrArena.ptr]
    sub     rax, [rdi + StrArena.base]
    pop     rbp
    ret

.au_zero:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_arena_used

; -----------------------------------------------------------------------------
; str_arena_remaining
;
; Return the number of bytes still available in the arena.
;
; Signature:
;   uint64_t str_arena_remaining(const StrArena *arena)
; -----------------------------------------------------------------------------

STR_FUNC str_arena_remaining

    test    rdi, rdi
    jz      .ar_zero

    mov     rax, [rdi + StrArena.end]
    sub     rax, [rdi + StrArena.ptr]
    pop     rbp
    ret

.ar_zero:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_arena_remaining

; -----------------------------------------------------------------------------
; str_arena_save / str_arena_restore
;
; Save and restore the arena cursor for scoped allocations.
; Allows allocating temporaries within a scope and freeing them
; all at once by restoring the saved cursor.
;
; Signature:
;   uint64_t str_arena_save(const StrArena *arena)
;   void str_arena_restore(StrArena *arena, uint64_t saved_ptr)
; -----------------------------------------------------------------------------

STR_FUNC str_arena_save

    test    rdi, rdi
    jz      .asv_zero

    mov     rax, [rdi + StrArena.ptr]
    pop     rbp
    ret

.asv_zero:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_arena_save

STR_FUNC str_arena_restore

    test    rdi, rdi
    jz      .arst_null

    ; validate: saved_ptr must be within [base, end]
    cmp     rsi, [rdi + StrArena.base]
    jb      .arst_null
    cmp     rsi, [rdi + StrArena.end]
    ja      .arst_null

    mov     [rdi + StrArena.ptr], rsi

.arst_null:
    pop     rbp
    ret

STR_ENDFUNC str_arena_restore