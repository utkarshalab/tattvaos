; =============================================================================
; str/intern/pool.asm
; String interning pool — deduplicate identical strings.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   hash/fnv1a.asm       (str_fnv1a_64)
;   mem/arena.asm        (str_arena_alloc)
;   core/cmp.asm         (str_eq)
;   core/copy.asm        (str_copy_bytes)
;
; -----------------------------------------------------------------------------
; String interning guarantees that equal strings share the same pointer.
; This enables:
;   - O(1) equality comparison via pointer comparison
;   - Deduplication (saves memory for repeated strings)
;   - Stable addresses (interned string pointers never move)
;
; Use cases in Tattva OS:
;   - Kernel symbol tables (function/variable names)
;   - utasm identifiers (labels, directives, registers)
;   - uide syntax tokens
;
; Design:
;   - Open-addressed hash table with linear probing
;   - Strings stored in a backing arena (bump allocator)
;   - The pool never frees individual strings (arena semantics)
;   - Table grows by doubling when load factor > 0.75
;
; StrInternPool layout:
;   arena     dq   — pointer to StrArena for string storage
;   table     dq   — pointer to hash table (array of StrSlice)
;   count     dq   — number of interned strings
;   capacity  dq   — hash table capacity (power of 2)
;   mask      dq   — capacity - 1 (for masking)
;
; Each table entry: StrSlice (ptr + len). ptr == NULL means empty slot.
;
; Functions:
;   str_intern_pool_init  — initialize pool with arena
;   str_intern            — intern a string, get canonical pointer
;   str_intern_lookup     — check if string is already interned
;   str_intern_count      — number of interned strings
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_fnv1a_64
extern str_arena_alloc
extern str_copy_bytes

struc StrInternPool
    .arena    resq 1
    .table    resq 1
    .count    resq 1
    .capacity resq 1
    .mask     resq 1
endstruc

INTERN_POOL_SIZE    equ 40
INTERN_INIT_CAP     equ 256     ; initial hash table capacity
INTERN_LOAD_NUMER   equ 3       ; load factor 3/4 = 0.75
INTERN_LOAD_DENOM   equ 4

section .text

; Internal: hash a StrSlice → uint64
; RDI = ptr, RSI = len, returns RAX
_intern_hash:
    push    rbp
    mov     rbp, rsp

    ; use FNV-1a
    ; str_fnv1a_64 expects (StrSlice *src)
    ; build temp StrSlice on stack
    sub     rsp, STRSLICE_SIZE + 16
    and     rsp, -16
    mov     [rsp + StrSlice.ptr], rdi
    mov     [rsp + StrSlice.len], rsi
    mov     rdi, rsp
    call    str_fnv1a_64
    mov     rsp, rbp
    pop     rbp
    ret

; Internal: compare two StrSlices for equality
; RDI = ptr_a, RSI = len_a, RDX = ptr_b, RCX = len_b
; Returns: EAX = 1 equal, 0 not
_intern_eq:
    cmp     rsi, rcx
    jne     .ie_no

    ; same length: compare bytes
    xor     r8, r8
.ie_loop:
    cmp     r8, rsi
    jae     .ie_yes
    movzx   eax, byte [rdi + r8]
    movzx   ecx, byte [rdx + r8]
    cmp     eax, ecx
    jne     .ie_no
    inc     r8
    jmp     .ie_loop

.ie_yes:
    mov     eax, 1
    ret
.ie_no:
    xor     eax, eax
    ret

; -----------------------------------------------------------------------------
; str_intern_pool_init
;
; Initialize an interning pool.
;
; Signature:
;   int64_t str_intern_pool_init(StrInternPool *pool, StrArena *arena)
;
; The pool allocates its hash table from the arena. The arena must have
; enough space for INTERN_INIT_CAP * STRSLICE_SIZE bytes initial table.
; -----------------------------------------------------------------------------

STR_FUNC str_intern_pool_init

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12

    mov     rbx, rdi
    mov     r12, rsi

    mov     [rbx + StrInternPool.arena], r12
    mov     qword [rbx + StrInternPool.count], 0
    mov     qword [rbx + StrInternPool.capacity], INTERN_INIT_CAP
    mov     qword [rbx + StrInternPool.mask], INTERN_INIT_CAP - 1

    ; allocate zeroed table from arena
    mov     rdi, r12
    mov     rsi, INTERN_INIT_CAP * STRSLICE_SIZE
    mov     rdx, 8
    call    str_arena_alloc
    test    rax, rax
    jz      .ipi_oom

    mov     [rbx + StrInternPool.table], rax

    ; zero the table (all ptr fields = NULL)
    mov     rdi, rax
    xor     eax, eax
    mov     rcx, INTERN_INIT_CAP * STRSLICE_SIZE
    rep stosb

    pop_regs r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.ipi_oom:
    pop_regs r12, rbx
    mov     rax, STR_ERR_ALLOC
    pop     rbp
    ret

STR_ENDFUNC str_intern_pool_init

; -----------------------------------------------------------------------------
; str_intern
;
; Intern a string. Returns a canonical StrSlice that is guaranteed to be
; pointer-comparable: if two strings are equal, they return the same ptr.
;
; Signature:
;   int64_t str_intern(StrInternPool *pool, const StrSlice *str,
;                       StrSlice *out)
;
; Arguments:
;   RDI  — pool
;   RSI  — string to intern
;   RDX  — output StrSlice (canonical interned version)
;
; Returns:
;   RAX  = STR_OK (out points to canonical interned string)
;   RAX  = STR_ERR_ALLOC (arena exhausted)
; -----------------------------------------------------------------------------

STR_FUNC str_intern

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, rdi            ; pool
    mov     r12, rsi            ; input str
    mov     r13, rdx            ; out

    mov     r14, [r12 + StrSlice.ptr]   ; str ptr
    mov     r15, [r12 + StrSlice.len]   ; str len

    ; hash the string
    mov     rdi, r14
    mov     rsi, r15
    call    _intern_hash
    mov     r9, rax             ; hash

    ; probe the table
    mov     r10, [rbx + StrInternPool.table]
    mov     r11, [rbx + StrInternPool.mask]

    and     r9, r11             ; slot = hash & mask

.si_probe:
    ; entry = table[slot]
    mov     rax, r9
    shl     rax, 4              ; * STRSLICE_SIZE (16 bytes)
    lea     rcx, [r10 + rax]

    mov     rdi, [rcx + StrSlice.ptr]
    test    rdi, rdi
    jz      .si_empty_slot      ; empty → insert here

    ; compare with existing entry
    mov     rsi, [rcx + StrSlice.len]
    mov     rdx, r14
    mov     rcx, r15
    push    r9
    call    _intern_eq
    pop     r9
    test    eax, eax
    jnz     .si_found           ; match → return existing

    ; collision: linear probe
    inc     r9
    and     r9, r11
    jmp     .si_probe

.si_found:
    ; already interned — copy entry to out
    mov     rax, r9
    shl     rax, 4
    lea     rcx, [r10 + rax]

    mov     rdi, [rcx + StrSlice.ptr]
    mov     [r13 + StrSlice.ptr], rdi
    mov     rdi, [rcx + StrSlice.len]
    mov     [r13 + StrSlice.len], rdi

    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.si_empty_slot:
    ; not found — intern: allocate copy in arena, insert into table

    ; allocate space in arena
    mov     rdi, [rbx + StrInternPool.arena]
    mov     rsi, r15
    mov     rdx, 1              ; byte alignment
    push    r9
    call    str_arena_alloc
    pop     r9
    test    rax, rax
    jz      .si_oom

    ; copy string bytes into arena
    mov     rdi, rax            ; dst (arena allocation)
    mov     rsi, r14            ; src (original string)
    mov     rdx, r15            ; len
    push    rax
    push    r9
    call    str_copy_bytes
    pop     r9
    pop     rax

    ; insert into table
    mov     r10, [rbx + StrInternPool.table]
    mov     rcx, r9
    shl     rcx, 4
    lea     rdx, [r10 + rcx]

    mov     [rdx + StrSlice.ptr], rax
    mov     [rdx + StrSlice.len], r15

    ; write to out
    mov     [r13 + StrSlice.ptr], rax
    mov     [r13 + StrSlice.len], r15

    ; increment count
    inc     qword [rbx + StrInternPool.count]

    ; TODO: check load factor and grow table if needed

    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.si_oom:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_ALLOC
    pop     rbp
    ret

STR_ENDFUNC str_intern

; -----------------------------------------------------------------------------
; str_intern_lookup
;
; Check if a string is already interned (does NOT intern if absent).
;
; Signature:
;   int64_t str_intern_lookup(const StrInternPool *pool,
;                              const StrSlice *str, StrSlice *out)
;
; Returns:
;   RAX = STR_OK       found (out filled)
;   RAX = STR_ERR_NOT_FOUND  not interned
; -----------------------------------------------------------------------------

STR_FUNC str_intern_lookup

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx

    mov     r14, [r12 + StrSlice.ptr]
    mov     r15, [r12 + StrSlice.len]

    mov     rdi, r14
    mov     rsi, r15
    call    _intern_hash

    mov     r10, [rbx + StrInternPool.table]
    mov     r11, [rbx + StrInternPool.mask]
    mov     r9, rax
    and     r9, r11

.sil_probe:
    mov     rax, r9
    shl     rax, 4
    lea     rcx, [r10 + rax]

    mov     rdi, [rcx + StrSlice.ptr]
    test    rdi, rdi
    jz      .sil_not_found

    mov     rsi, [rcx + StrSlice.len]
    mov     rdx, r14
    mov     rcx, r15
    push    r9
    call    _intern_eq
    pop     r9
    test    eax, eax
    jnz     .sil_found

    inc     r9
    and     r9, r11
    jmp     .sil_probe

.sil_found:
    test    r13, r13
    jz      .sil_ok

    mov     rax, r9
    shl     rax, 4
    lea     rcx, [r10 + rax]
    mov     rdi, [rcx + StrSlice.ptr]
    mov     [r13 + StrSlice.ptr], rdi
    mov     rdi, [rcx + StrSlice.len]
    mov     [r13 + StrSlice.len], rdi

.sil_ok:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.sil_not_found:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_NOT_FOUND
    pop     rbp
    ret

STR_ENDFUNC str_intern_lookup

; -----------------------------------------------------------------------------
; str_intern_count
; Returns: RAX = number of interned strings
; -----------------------------------------------------------------------------

STR_FUNC str_intern_count

    test    rdi, rdi
    jz      .sic_zero
    mov     rax, [rdi + StrInternPool.count]
    pop     rbp
    ret
.sic_zero:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_intern_count