; ============================================================================
; Unit Test — Arena Allocator (src/core/arena.asm)
; ============================================================================
; test_arena_suite -> eax = failed cases. Each case returns 0 (pass) or 1.
; Covers init (and a zero size refused), allocation (16-byte rounding,
; distinct non-overlapping blocks, zero size, running out leaving the arena
; as it was), aligned allocation (the asked alignment, 16 by default, out of
; memory), mark / rewind (and a mark outside refused), free_all, used /
; available, contains, child arenas (inside the parent, too big refused,
; destroy giving back only the child's part).

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

extern arena_init
extern arena_create
extern arena_alloc
extern arena_alloc_aligned
extern arena_mark
extern arena_rewind
extern arena_free_all
extern arena_used
extern arena_available
extern arena_contains
extern arena_destroy

%define A_BASE      0                   ; Arena fields (struct_offsets.inc)
%define A_CURSOR    8
%define A_LIMIT     16
%define A_PARENT    24
%define STORE_SIZE  4096

section .text

global test_arena_suite
global test_arena_main
test_arena_suite:
test_arena_main:
    push rbx
    xor ebx, ebx
%macro CASE 1
    call %1
    add ebx, eax
%endmacro
    CASE ta_init
    CASE ta_init_zero
    CASE ta_alloc_round
    CASE ta_alloc_distinct
    CASE ta_alloc_zero
    CASE ta_alloc_oom
    CASE ta_aligned
    CASE ta_aligned_default
    CASE ta_aligned_oom
    CASE ta_mark_rewind
    CASE ta_rewind_outside
    CASE ta_free_all
    CASE ta_contains
    CASE ta_child
    CASE ta_child_too_big
    CASE ta_child_destroy
    mov eax, ebx
    pop rbx
    ret

; a fresh arena over the storage -> rax = 0
fresh:
    sub rsp, 8
    lea rdi, [rel arena]
    lea rsi, [rel store]
    mov edx, STORE_SIZE
    call arena_init
    add rsp, 8
    ret

%macro FAIL_IF 1                        ; condition code: the case fails when it holds
    j%1 .fail
%endmacro

ta_init:
    sub rsp, 8
    call fresh
    test rax, rax
    FAIL_IF nz
    lea rcx, [rel store]
    cmp [rel arena + A_BASE], rcx
    FAIL_IF ne
    cmp [rel arena + A_CURSOR], rcx
    FAIL_IF ne
    add rcx, STORE_SIZE
    cmp [rel arena + A_LIMIT], rcx
    FAIL_IF ne
    cmp qword [rel arena + A_PARENT], 0
    FAIL_IF ne
    lea rdi, [rel arena]
    call arena_used
    test rax, rax
    FAIL_IF nz
    lea rdi, [rel arena]
    call arena_available
    cmp rax, STORE_SIZE
    FAIL_IF ne
    xor eax, eax
    add rsp, 8
    ret
.fail:
    mov eax, 1
    add rsp, 8
    ret

ta_init_zero:
    sub rsp, 8
    lea rdi, [rel arena]
    lea rsi, [rel store]
    xor edx, edx
    call arena_init
    cmp rax, -(EINVAL)
    FAIL_IF ne
    xor eax, eax
    add rsp, 8
    ret
.fail:
    mov eax, 1
    add rsp, 8
    ret

; 1 byte takes 16: the first block at the base, used 16
ta_alloc_round:
    sub rsp, 8
    call fresh
    lea rdi, [rel arena]
    mov esi, 1
    call arena_alloc
    lea rcx, [rel store]
    cmp rax, rcx
    FAIL_IF ne
    lea rdi, [rel arena]
    call arena_used
    cmp rax, 16
    FAIL_IF ne
    xor eax, eax
    add rsp, 8
    ret
.fail:
    mov eax, 1
    add rsp, 8
    ret

; 24 then 8 bytes: 16-aligned, the second after the first's 32
ta_alloc_distinct:
    push rbx
    call fresh
    lea rdi, [rel arena]
    mov esi, 24
    call arena_alloc
    mov rbx, rax
    lea rdi, [rel arena]
    mov esi, 8
    call arena_alloc
    test rbx, rbx
    FAIL_IF z
    test rax, rax
    FAIL_IF z
    lea rcx, [rbx + 32]
    cmp rax, rcx
    FAIL_IF ne
    test al, 15
    FAIL_IF nz
    xor eax, eax
    pop rbx
    ret
.fail:
    mov eax, 1
    pop rbx
    ret

ta_alloc_zero:
    sub rsp, 8
    call fresh
    lea rdi, [rel arena]
    xor esi, esi
    call arena_alloc
    test rax, rax
    FAIL_IF nz
    lea rdi, [rel arena]
    call arena_used
    test rax, rax
    FAIL_IF nz
    xor eax, eax
    add rsp, 8
    ret
.fail:
    mov eax, 1
    add rsp, 8
    ret

; more than is left: 0, and nothing taken
ta_alloc_oom:
    sub rsp, 8
    call fresh
    lea rdi, [rel arena]
    mov esi, 100
    call arena_alloc
    lea rdi, [rel arena]
    mov esi, STORE_SIZE
    call arena_alloc
    test rax, rax
    FAIL_IF nz
    lea rdi, [rel arena]
    call arena_used
    cmp rax, 112
    FAIL_IF ne
    xor eax, eax
    add rsp, 8
    ret
.fail:
    mov eax, 1
    add rsp, 8
    ret

; 16 bytes, then 64-aligned: aligned to 64, at or after the first's end
ta_aligned:
    push rbx
    call fresh
    lea rdi, [rel arena]
    mov esi, 16
    call arena_alloc
    lea rbx, [rax + 16]
    lea rdi, [rel arena]
    mov esi, 8
    mov edx, 64
    call arena_alloc_aligned
    test rax, rax
    FAIL_IF z
    test al, 63
    FAIL_IF nz
    cmp rax, rbx
    FAIL_IF b
    lea rcx, [rbx + 64]
    cmp rax, rcx
    FAIL_IF ae
    xor eax, eax
    pop rbx
    ret
.fail:
    mov eax, 1
    pop rbx
    ret

; alignment 0 means 16
ta_aligned_default:
    sub rsp, 8
    call fresh
    lea rdi, [rel arena]
    mov esi, 1
    call arena_alloc
    lea rdi, [rel arena]
    mov esi, 1
    xor edx, edx
    call arena_alloc_aligned
    test rax, rax
    FAIL_IF z
    test al, 15
    FAIL_IF nz
    xor eax, eax
    add rsp, 8
    ret
.fail:
    mov eax, 1
    add rsp, 8
    ret

ta_aligned_oom:
    sub rsp, 8
    call fresh
    lea rdi, [rel arena]
    mov esi, STORE_SIZE + 1
    mov edx, 16
    call arena_alloc_aligned
    test rax, rax
    FAIL_IF nz
    lea rdi, [rel arena]
    call arena_used
    test rax, rax
    FAIL_IF nz
    xor eax, eax
    add rsp, 8
    ret
.fail:
    mov eax, 1
    add rsp, 8
    ret

; mark, take 48, rewind: the cursor back at the mark, the next block there
ta_mark_rewind:
    push rbx
    call fresh
    lea rdi, [rel arena]
    mov esi, 32
    call arena_alloc
    lea rdi, [rel arena]
    call arena_mark
    mov rbx, rax
    lea rdi, [rel arena]
    mov esi, 48
    call arena_alloc
    lea rdi, [rel arena]
    mov rsi, rbx
    call arena_rewind
    test rax, rax
    FAIL_IF nz
    cmp [rel arena + A_CURSOR], rbx
    FAIL_IF ne
    lea rdi, [rel arena]
    mov esi, 16
    call arena_alloc
    cmp rax, rbx
    FAIL_IF ne
    xor eax, eax
    pop rbx
    ret
.fail:
    mov eax, 1
    pop rbx
    ret

ta_rewind_outside:
    sub rsp, 8
    call fresh
    lea rdi, [rel arena]
    lea rsi, [rel store - 16]
    call arena_rewind
    cmp rax, -(EINVAL)
    FAIL_IF ne
    lea rdi, [rel arena]
    lea rsi, [rel store + STORE_SIZE + 16]
    call arena_rewind
    cmp rax, -(EINVAL)
    FAIL_IF ne
    lea rcx, [rel store]
    cmp [rel arena + A_CURSOR], rcx
    FAIL_IF ne
    xor eax, eax
    add rsp, 8
    ret
.fail:
    mov eax, 1
    add rsp, 8
    ret

ta_free_all:
    sub rsp, 8
    call fresh
    lea rdi, [rel arena]
    mov esi, 500
    call arena_alloc
    lea rdi, [rel arena]
    call arena_free_all
    test rax, rax
    FAIL_IF nz
    lea rdi, [rel arena]
    call arena_used
    test rax, rax
    FAIL_IF nz
    xor eax, eax
    add rsp, 8
    ret
.fail:
    mov eax, 1
    add rsp, 8
    ret

; the base and the last byte inside; one before the base and the limit outside
ta_contains:
    sub rsp, 8
    call fresh
    lea rdi, [rel arena]
    lea rsi, [rel store]
    call arena_contains
    cmp rax, 1
    FAIL_IF ne
    lea rdi, [rel arena]
    lea rsi, [rel store + STORE_SIZE - 1]
    call arena_contains
    cmp rax, 1
    FAIL_IF ne
    lea rdi, [rel arena]
    lea rsi, [rel store - 1]
    call arena_contains
    test rax, rax
    FAIL_IF nz
    lea rdi, [rel arena]
    lea rsi, [rel store + STORE_SIZE]
    call arena_contains
    test rax, rax
    FAIL_IF nz
    xor eax, eax
    add rsp, 8
    ret
.fail:
    mov eax, 1
    add rsp, 8
    ret

; a 1024-byte child after 32 bytes of the parent: inside it, its own limit,
; the parent's cursor past it
ta_child:
    push rbx
    call fresh
    lea rdi, [rel arena]
    mov esi, 32
    call arena_alloc
    lea rdi, [rel arena]
    mov esi, 1024
    lea rdx, [rel child]
    call arena_create
    test rax, rax
    FAIL_IF nz
    mov rbx, [rel child + A_BASE]
    lea rcx, [rel store + 32]
    cmp rbx, rcx
    FAIL_IF b
    lea rcx, [rbx + 1024]
    cmp [rel child + A_LIMIT], rcx
    FAIL_IF ne
    cmp [rel child + A_CURSOR], rbx
    FAIL_IF ne
    lea rcx, [rel arena]
    cmp [rel child + A_PARENT], rcx
    FAIL_IF ne
    lea rcx, [rbx + 1024]
    cmp [rel arena + A_CURSOR], rcx
    FAIL_IF b
    lea rdi, [rel child]
    mov esi, 16
    call arena_alloc
    cmp rax, rbx
    FAIL_IF ne
    xor eax, eax
    pop rbx
    ret
.fail:
    mov eax, 1
    pop rbx
    ret

ta_child_too_big:
    sub rsp, 8
    call fresh
    lea rdi, [rel arena]
    mov esi, STORE_SIZE * 2
    lea rdx, [rel child]
    call arena_create
    cmp rax, -(ENOMEM)
    FAIL_IF ne
    lea rdi, [rel arena]
    call arena_used
    test rax, rax
    FAIL_IF nz
    xor eax, eax
    add rsp, 8
    ret
.fail:
    mov eax, 1
    add rsp, 8
    ret

; destroying a child gives back its part only: the parent's earlier
; allocation stays, its cursor goes back to where the child began
ta_child_destroy:
    push rbx
    call fresh
    lea rdi, [rel arena]
    mov esi, 64
    call arena_alloc
    lea rdi, [rel arena]
    mov esi, 256
    lea rdx, [rel child]
    call arena_create
    test rax, rax
    FAIL_IF nz
    mov rbx, [rel child + A_BASE]
    lea rdi, [rel child]
    call arena_destroy
    test rax, rax
    FAIL_IF nz
    cmp [rel arena + A_CURSOR], rbx
    FAIL_IF ne
    lea rdi, [rel arena]
    call arena_used
    cmp rax, 64
    FAIL_IF b
    xor eax, eax
    pop rbx
    ret
.fail:
    mov eax, 1
    pop rbx
    ret

section .bss
alignb 64
store:      resb STORE_SIZE
arena:      resq 4
child:      resq 4
