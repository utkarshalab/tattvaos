; ============================================================================
; Arena Allocator — Complete Implementation
; Bump allocator with mark/rewind, child arenas, alignment
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
;   OUT: rax = 0 OK, negative error
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
; arena_alloc
;   Allocate aligned memory from arena
;   IN:  rdi = arena*, rsi = size (bytes)
;   OUT: rax = pointer, 0 on OOM
; ---------------------------------------------------------------------------
global arena_alloc
arena_alloc:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    test r12, r12
    jz .fail
    mov r13, [rbx + Arena.cursor]
    mov rax, [rbx + Arena.limit]
    lea rcx, [r13 + r12 + 15]
    and rcx, ~15
    cmp rcx, rax
    ja .oom
    mov [rbx + Arena.cursor], rcx
    mov rax, r13
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.oom:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.fail:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; arena_alloc_aligned
;   Allocate with explicit alignment (power of 2)
;   IN:  rdi = arena*, rsi = size, rdx = alignment
;   OUT: rax = pointer, 0 on OOM
; ---------------------------------------------------------------------------
global arena_alloc_aligned
arena_alloc_aligned:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    test r12, r12
    jz .fail
    test r13, r13
    jz .fail
    mov rax, r13
    dec rax
    test rax, r13
    jnz .fail
    mov r14, [rbx + Arena.cursor]
    lea rax, [r14 + r13 - 1]
    mov rcx, r13
    dec rcx
    not rcx
    and rax, rcx
    mov r14, rax
    mov rax, [rbx + Arena.limit]
    lea rcx, [r14 + r12]
    cmp rcx, rax
    ja .oom
    mov [rbx + Arena.cursor], rcx
    mov rax, r14
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.oom:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.fail:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; arena_create_child
;   Create sub-arena from parent
;   IN:  rdi = parent arena*, rsi = child arena*, rdx = size
;   OUT: rax = 0 OK, negative error
; ---------------------------------------------------------------------------
global arena_create_child
arena_create_child:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    test r13, r13
    jz .fail
    mov rax, [rbx + Arena.cursor]
    mov rcx, [rbx + Arena.limit]
    lea rdx, [rax + r13 + 15]
    and rdx, -16  ; ~15 = -16 (16-byte alignment)
    cmp rdx, rcx
    ja .oom
    mov qword [r12 + Arena.base], rax
    mov qword [r12 + Arena.cursor], rax
    mov qword [r12 + Arena.limit], rdx
    mov qword [r12 + Arena.parent], rbx
    mov qword [rbx + Arena.cursor], rdx
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.fail:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; arena_destroy_child
;   Destroy child arena, return unused space to parent
;   IN:  rdi = child arena*
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global arena_destroy_child
arena_destroy_child:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    ASSERT_PTR rbx
    mov r12, [rbx + Arena.parent]
    test r12, r12
    jz .fail
    mov rax, [rbx + Arena.cursor]
    mov qword [r12 + Arena.cursor], rax
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret
.fail:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; arena_mark
;   Save current cursor position
;   IN:  rdi = arena*
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
;   Restore cursor to mark (free allocations after mark)
;   IN:  rdi = arena*, rsi = mark
;   OUT: rax = 0 OK, negative error
; ---------------------------------------------------------------------------
global arena_rewind
arena_rewind:
    PROLOGUE
    ASSERT_PTR rdi
    mov rax, [rdi + Arena.base]
    cmp rsi, rax
    jb .fail
    mov rax, [rdi + Arena.limit]
    cmp rsi, rax
    ja .fail
    mov qword [rdi + Arena.cursor], rsi
    xor rax, rax
    leave
    ret
.fail:
    mov rax, -(EINVAL)
    leave
    ret

; ---------------------------------------------------------------------------
; arena_free_all
;   Reset arena to initial state
;   IN:  rdi = arena*
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global arena_free_all
arena_free_all:
    PROLOGUE
    ASSERT_PTR rdi
    mov rax, [rdi + Arena.base]
    mov qword [rdi + Arena.cursor], rax
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; arena_used
;   Get bytes used in arena
;   IN:  rdi = arena*
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
; arena_remaining
;   Get bytes remaining in arena
;   IN:  rdi = arena*
;   OUT: rax = remaining bytes
; ---------------------------------------------------------------------------
global arena_remaining
arena_remaining:
    PROLOGUE
    ASSERT_PTR rdi
    mov rax, [rdi + Arena.limit]
    sub rax, [rdi + Arena.cursor]
    leave
    ret

section .data
global arena_version
arena_version: dq 0x010000