; ============================================================================
; LZ — Hash-Chain Match Finder (LZ77) for Deflate/CRP
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

section .text

%define LZ_WINDOW_BITS   15
%define LZ_WINDOW_SIZE   (1 << LZ_WINDOW_BITS)
%define LZ_HASH_BITS     14
%define LZ_HASH_SIZE     (1 << LZ_HASH_BITS)
%define LZ_MIN_MATCH     3
%define LZ_MAX_MATCH     258

struc LzCtx {
    .head:          resq 1
    .prev:          resq 1
    .window_start:  resq 1
}
%define LzCtx_size    24

; ---------------------------------------------------------------------------
; lz_init
; ---------------------------------------------------------------------------
global lz_init
lz_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov rdi, r12
    mov rsi, LZ_HASH_SIZE
    shl rsi, 2
    call arena_alloc
    test rax, rax
    jz .oom
    mov qword [rbx + LzCtx.head], rax
    mov rdi, r12
    mov rsi, LZ_WINDOW_SIZE
    shl rsi, 2
    call arena_alloc
    test rax, rax
    jz .oom
    mov qword [rbx + LzCtx.prev], rax
    mov qword [rbx + LzCtx.window_start], 0
    ; clear head to -1
    mov rdi, [rbx + LzCtx.head]
    mov ecx, LZ_HASH_SIZE
    mov eax, -1
    rep stosd
    xor rax, rax
    ret
.oom:
    RETURN_ERROR ENOMEM

; ---------------------------------------------------------------------------
; lz_hash3
; ---------------------------------------------------------------------------
global lz_hash3
lz_hash3:
    PROLOGUE
    ASSERT_PTR rdi
    movzx eax, byte [rdi]
    shl eax, 10
    movzx edx, byte [rdi + 1]
    shl edx, 5
    or eax, edx
    movzx edx, byte [rdi + 2]
    or eax, edx
    and eax, LZ_HASH_SIZE - 1
    ret

; ---------------------------------------------------------------------------
; lz_find_match
;   IN: rdi=ctx, rsi=data, rdx=pos, rcx=remain
;   OUT: rax = length (0 if none), rdx = distance
; ---------------------------------------------------------------------------
global lz_find_match
lz_find_match:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    cmp r14, LZ_MIN_MATCH
    jb .none
    ; hash
    mov rdi, r12
    add rdi, r13
    call lz_hash3
    mov r15d, eax
    mov rax, [rbx + LzCtx.head]
    mov r10d, [rax + r15 * 4]  ; prev pos with same hash
    ; update head/prev
    mov [rax + r15 * 4], r13d
    mov rax, [rbx + LzCtx.prev]
    mov rcx, r13
    and rcx, LZ_WINDOW_SIZE - 1
    mov [rax + rcx * 4], r10d
    cmp r10d, 0
    jl .none
    ; distance check
    mov eax, r13d
    sub eax, r10d
    jbe .none
    cmp eax, LZ_WINDOW_SIZE
    ja .none
    mov r11d, eax  ; distance
    ; match length
    mov rax, r14
    cmp rax, LZ_MAX_MATCH
    jbe .len_ok
    mov rax, LZ_MAX_MATCH
.len_ok:
    xor ecx, ecx
.cmp:
    cmp rcx, rax
    jae .found
    mov r8b, [r12 + r13 + rcx]
    mov r9b, [r12 + r10 + rcx]
    cmp r8b, r9b
    jne .found
    inc rcx
    jmp .cmp
.found:
    cmp rcx, LZ_MIN_MATCH
    jb .none
    mov rax, rcx
    mov rdx, r11
    ret
.none:
    xor rax, rax
    xor rdx, rdx
    ret

section .data
global lz_version
lz_version: dq 0x010000
