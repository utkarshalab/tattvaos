%ifndef GUARD_LIB_STR_MEM_ALLOC_ASM
%define GUARD_LIB_STR_MEM_ALLOC_ASM
; =============================================================================
; str/mem/alloc.asm
; Heap allocation wrappers for the str library.
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
; These are thin wrappers around OS syscalls (Linux mmap/munmap)
; and a minimal free-list allocator.
;
; For most str library operations, prefer the arena allocator (arena.asm)
; which is faster and avoids fragmentation.
;
; These functions exist for:
;   - StrBuf dynamic growth (realloc semantics)
;   - Large string operations that exceed arena capacity
;   - Standalone use outside Tattva OS kernel context
;
; Linux syscall numbers (x86_64):
;   mmap   = 9
;   munmap = 11
;   brk    = 12
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

; mmap flags
PROT_READ       equ 0x1
PROT_WRITE      equ 0x2
MAP_PRIVATE     equ 0x2
MAP_ANONYMOUS   equ 0x20

; syscall numbers (Linux x86_64)
SYS_MMAP        equ 9
SYS_MUNMAP      equ 11

section .text

; -----------------------------------------------------------------------------
; str_alloc
;
; Allocate size bytes of zeroed memory.
; Uses mmap(NULL, size, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANON, -1, 0)
;
; Signature:
;   void *str_alloc(uint64_t size)
;
; Arguments:
;   RDI  — size in bytes
;
; Returns:
;   RAX  — pointer to allocated memory (page-aligned)
;   RAX  = null (0) if allocation failed
; -----------------------------------------------------------------------------

STR_FUNC str_alloc

    test    rdi, rdi
    jz      .alloc_zero_size

    ; round up to page size (4096)
    add     rdi, 4095
    and     rdi, ~4095

    ; mmap(NULL, size, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANON, -1, 0)
    mov     rax, SYS_MMAP
    xor     edi, edi            ; addr = NULL  -- wait, rdi = size
    ; need to pass size in rsi, not rdi
    ; fix register setup:
    mov     rsi, rdi            ; size (already set)
    xor     edi, edi            ; addr = NULL

    mov     rax, SYS_MMAP
    ; rdi = NULL (addr)
    ; rsi = size
    mov     rdx, PROT_READ | PROT_WRITE
    mov     r10, MAP_PRIVATE | MAP_ANONYMOUS
    mov     r8, -1              ; fd = -1
    xor     r9d, r9d            ; offset = 0

    syscall

    ; check for error: mmap returns -1..-4095 on error
    cmp     rax, -4096
    jbe     .alloc_ok           ; unsigned compare: > 4095 means valid ptr

    xor     eax, eax            ; return null on error
    pop     rbp
    ret

.alloc_ok:
    pop     rbp
    ret

.alloc_zero_size:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_alloc

; -----------------------------------------------------------------------------
; str_alloc_size
;
; Like str_alloc but returns the actual allocated size (rounded to page).
;
; Signature:
;   void *str_alloc_size(uint64_t size, uint64_t *out_actual_size)
;
; Arguments:
;   RDI  — requested size
;   RSI  — pointer to uint64_t for actual size (may be null)
; -----------------------------------------------------------------------------

STR_FUNC str_alloc_size

    push_regs rbx

    mov     rbx, rsi            ; save out_actual_size

    ; round up to page
    mov     rsi, rdi
    add     rsi, 4095
    and     rsi, ~4095
    push    rsi                 ; save rounded size

    ; mmap
    mov     rax, SYS_MMAP
    xor     edi, edi
    mov     rdx, PROT_READ | PROT_WRITE
    mov     r10, MAP_PRIVATE | MAP_ANONYMOUS
    mov     r8, -1
    xor     r9d, r9d
    syscall

    pop     rcx                 ; rounded size

    cmp     rax, -4096
    jbe     .as_ok

    xor     eax, eax
    pop_regs rbx
    pop     rbp
    ret

.as_ok:
    test    rbx, rbx
    jz      .as_done
    mov     [rbx], rcx

.as_done:
    pop_regs rbx
    pop     rbp
    ret

STR_ENDFUNC str_alloc_size

; -----------------------------------------------------------------------------
; str_free
;
; Free memory allocated by str_alloc.
;
; Signature:
;   int64_t str_free(void *ptr, uint64_t size)
;
; Arguments:
;   RDI  — pointer (must be page-aligned, from str_alloc)
;   RSI  — size (must match allocation size, rounded to page)
;
; Returns:
;   RAX  = STR_OK or error
; -----------------------------------------------------------------------------

STR_FUNC str_free

    test    rdi, rdi
    jz      .free_null

    ; round size up to page
    add     rsi, 4095
    and     rsi, ~4095

    mov     rax, SYS_MUNMAP
    syscall

    test    rax, rax
    jnz     .free_err

    xor     eax, eax
    pop     rbp
    ret

.free_null:
    xor     eax, eax
    pop     rbp
    ret

.free_err:
    mov     rax, STR_ERR_ALLOC
    pop     rbp
    ret

STR_ENDFUNC str_free

; -----------------------------------------------------------------------------
; str_realloc
;
; Resize an allocation. Copies old data to new region.
; Old ptr is freed. Returns new pointer.
;
; Signature:
;   void *str_realloc(void *old_ptr, uint64_t old_size,
;                      uint64_t new_size)
;
; Arguments:
;   RDI  — old pointer (or null for fresh alloc)
;   RSI  — old size
;   RDX  — new size
;
; Returns:
;   RAX  — new pointer, or null on failure
; -----------------------------------------------------------------------------

STR_FUNC str_realloc

    ; null ptr → just alloc
    test    rdi, rdi
    jz      .realloc_fresh

    ; same size → return same ptr
    cmp     rsi, rdx
    je      .realloc_same

    push_regs rbx, r12, r13

    mov     rbx, rdi            ; old ptr
    mov     r12, rsi            ; old size
    mov     r13, rdx            ; new size

    ; allocate new region
    mov     rdi, r13
    call    str_alloc
    test    rax, rax
    jz      .realloc_oom

    ; copy min(old_size, new_size) bytes
    push    rax                 ; save new ptr

    mov     rdi, rax            ; dst
    mov     rsi, rbx            ; src

    mov     rcx, r12
    cmp     rcx, r13
    jbe     .realloc_copy_old
    mov     rcx, r13

.realloc_copy_old:
    push    rcx
    rep movsb
    pop     rcx

    ; free old
    pop     rax                 ; new ptr
    push    rax

    mov     rdi, rbx
    mov     rsi, r12
    call    str_free

    pop     rax

    pop_regs r13, r12, rbx
    pop     rbp
    ret

.realloc_oom:
    pop_regs r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.realloc_fresh:
    mov     rdi, rdx
    pop     rbp
    jmp     str_alloc

.realloc_same:
    mov     rax, rdi
    pop     rbp
    ret

STR_ENDFUNC str_realloc
%endif ; GUARD_LIB_STR_MEM_ALLOC_ASM
