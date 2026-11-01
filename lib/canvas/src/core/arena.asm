; ============================================================================
; Arena Allocator — Bump Allocator with Mark/Rewind
; Core memory management for Canvas (per-client, per-frame, global)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/struct_offsets.inc"

section .text

; ---------------------------------------------------------------------------
; arena_init
;   Initialize arena from existing memory region
;   IN:  rdi = arena pointer (Arena*)
;        rsi = base address
;        rdx = size (bytes)
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global arena_init
arena_init:
    PROLOGUE
    ASSERT_PTR rdi
    ASSERT_PTR rsi
    test rdx, rdx
    jz .fail

    mov qword [rdi + Arena.base], rsi
    mov qword [rdi + Arena.cursor], rsi
    lea rax, [rsi + rdx]
    mov qword [rdi + Arena.limit], rax
    mov qword [rdi + Arena.parent], 0
    xor rax, rax
    leave
    ret
.fail:
    mov rax, -(EINVAL)
    leave
    ret

; ---------------------------------------------------------------------------
; arena_create
;   Create sub-arena from parent (for per-client, per-frame)
;   IN:  rdi = parent arena (Arena*)
;        rsi = size (bytes)
;        rdx = child arena pointer (Arena*) - pre-allocated
;   OUT: rax = 0 OK, negative error
; ---------------------------------------------------------------------------
global arena_create
arena_create:
    PROLOGUE_SAVE rbx, r12, r13
    sub rsp, 8
    mov rbx, rdi        ; parent
    mov r12, rdx        ; child arena struct
    mov r13, rsi        ; size (kept across the call)
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Allocate from parent
    mov rdi, rbx
    mov rsi, r13
    mov rdx, 16         ; alignment
    call arena_alloc_aligned
    test rax, rax
    jz .fail

    ; Initialize child arena
    mov qword [r12 + Arena.base], rax
    mov qword [r12 + Arena.cursor], rax
    lea rdx, [rax + r13]
    mov qword [r12 + Arena.limit], rdx
    mov qword [r12 + Arena.parent], rbx
    xor rax, rax
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.fail:
    mov rax, -(ENOMEM)
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; arena_alloc
;   Allocate from arena (16-byte aligned)
;   IN:  rdi = arena pointer
;        rsi = size (bytes)
;   OUT: rax = pointer, 0 on OOM
; ---------------------------------------------------------------------------
global arena_alloc
arena_alloc:
    PROLOGUE
    ASSERT_PTR rdi
    test rsi, rsi
    jz .zero
    ; Align size to 16 bytes
    add rsi, 15
    and rsi, ~15
    jmp .alloc
.zero:
    xor rax, rax
    leave
    ret
.alloc:
    mov rdx, [rdi + Arena.cursor]
    mov rcx, [rdi + Arena.limit]
    lea rax, [rdx + rsi]
    cmp rax, rcx
    ja .oom
    mov [rdi + Arena.cursor], rax
    mov rax, rdx                    ; return allocation start, not new cursor
    leave
    ret
.oom:
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; arena_alloc_aligned
;   Allocate with custom alignment (power of 2)
;   IN:  rdi = arena, rsi = size, rdx = alignment (power of 2, 0=16)
;   OUT: rax = aligned pointer, 0 on OOM
; ---------------------------------------------------------------------------
global arena_alloc_aligned
arena_alloc_aligned:
    PROLOGUE
    ASSERT_PTR rdi
    test rsi, rsi
    jz .zero
    test rdx, rdx
    jnz .has_align
    mov rdx, 16
.has_align:
%if DEBUG_BUILD
    lea rcx, [rdx - 1]              ; a power of two: align & (align - 1) == 0
    test rdx, rcx
    jz .pow2
    call panic_unaligned
.pow2:
%endif
    mov rcx, [rdi + Arena.cursor]
    ; Align cursor up: (cursor + align - 1) & -align
    add rcx, rdx
    dec rcx
    neg rdx
    and rcx, rdx
    mov rdx, [rdi + Arena.limit]
    lea rax, [rcx + rsi]
    cmp rax, rdx
    ja .oom
    mov [rdi + Arena.cursor], rax
    mov rax, rcx
    leave
    ret
.zero:
    xor rax, rax
    leave
    ret
.oom:
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; arena_mark
;   Save current cursor position
;   IN:  rdi = arena
;   OUT: rax = mark (cursor value)
; ---------------------------------------------------------------------------
global arena_mark
arena_mark:
    PROLOGUE
    ASSERT_PTR rdi
    mov rax, [rdi + Arena.cursor]
    leave
    ret

; ---------------------------------------------------------------------------
; arena_rewind
;   Restore cursor to mark (free all allocations after mark)
;   IN:  rdi = arena, rsi = mark
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global arena_rewind
arena_rewind:
    PROLOGUE
    ASSERT_PTR rdi
    mov rcx, [rdi + Arena.base]
    cmp rsi, rcx
    jb .invalid
    mov rcx, [rdi + Arena.limit]
    cmp rsi, rcx
    ja .invalid
    mov [rdi + Arena.cursor], rsi
    xor rax, rax
    leave
    ret
.invalid:
    mov rax, -(EINVAL)
    leave
    ret

; ---------------------------------------------------------------------------
; arena_free_all
;   Reset arena to base (free everything)
;   IN:  rdi = arena
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global arena_free_all
arena_free_all:
    PROLOGUE
    ASSERT_PTR rdi
    mov rax, [rdi + Arena.base]
    mov [rdi + Arena.cursor], rax
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; arena_free
;   Release one allocation from a monotonic arena.
;   Individual allocations cannot be reclaimed without invalidating newer
;   allocations, so destruction is intentionally deferred to rewind/free_all.
;   IN:  rdi = arena, rsi = allocation
;   OUT: rax is preserved (some destruction walks keep their next link here)
; ---------------------------------------------------------------------------
global arena_free
arena_free:
    ret

; ---------------------------------------------------------------------------
; arena_used
;   Get bytes used in arena
;   IN:  rdi = arena
;   OUT: rax = used bytes
; ---------------------------------------------------------------------------
global arena_used
arena_used:
    PROLOGUE
    ASSERT_PTR rdi
    mov rax, [rdi + Arena.cursor]
    sub rax, [rdi + Arena.base]
    leave
    ret

; ---------------------------------------------------------------------------
; arena_available
;   Get bytes remaining in arena
;   IN:  rdi = arena
;   OUT: rax = available bytes
; ---------------------------------------------------------------------------
global arena_available
arena_available:
    PROLOGUE
    ASSERT_PTR rdi
    mov rax, [rdi + Arena.limit]
    sub rax, [rdi + Arena.cursor]
    leave
    ret

; ---------------------------------------------------------------------------
; arena_contains
;   Check if pointer is within arena
;   IN:  rdi = arena, rsi = pointer
;   OUT: rax = 1 if inside, 0 if outside
; ---------------------------------------------------------------------------
global arena_contains
arena_contains:
    PROLOGUE
    ASSERT_PTR rdi
    mov rax, [rdi + Arena.base]
    cmp rsi, rax
    jb .outside
    mov rax, [rdi + Arena.limit]
    cmp rsi, rax
    jae .outside
    mov rax, 1
    leave
    ret
.outside:
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; arena_destroy
;   Destroy arena (if it has parent, return memory to parent)
;   IN:  rdi = arena
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global arena_destroy
arena_destroy:
    PROLOGUE
    ASSERT_PTR rdi
    mov rax, [rdi + Arena.parent]
    test rax, rax
    jz .no_parent
    ; Return memory to parent by rewinding parent to our base
    mov rsi, [rdi + Arena.base]     ; ours, not the parent's
    push rdi
    sub rsp, 8
    mov rdi, rax
    call arena_rewind
    add rsp, 8
    pop rdi
.no_parent:
    xor rax, rax
    leave
    ret

section .data

; Arena structure definition (for reference)
; struc Arena
;     .base:    resq 1
;     .cursor:  resq 1
;     .limit:   resq 1
;     .parent:  resq 1
; endstruc

global arena_version
arena_version: dq 0x010000
