; =============================================================================
; Tattva OS — lib/ucmp/mem/arena.asm
; =============================================================================
; Zero-Allocation Memory Arena Allocator for Streaming Buffers.
;
; Provides fast, lock-free linear memory allocation for sliding window ring
; buffers and Huffman tree building without kernel heap overhead.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%include "lib/ucmp/include/ucmp.inc"
%include "lib/ucmp/arch/common/macros.inc"

struc ucmp_arena_t
    .base_ptr:          resq 1      ; Base address of preallocated arena memory
    .capacity:          resq 1      ; Total size in bytes
    .offset:            resq 1      ; Current allocation offset
endstruc

section .text

global ucmp_arena_init
global ucmp_arena_alloc
global ucmp_arena_reset

; -----------------------------------------------------------------------------
; ucmp_arena_init
;
; Inputs:
;   RDI = Pointer to ucmp_arena_t state structure
;   RSI = Base address of buffer
;   RDX = Capacity in bytes
; -----------------------------------------------------------------------------
align 32
ucmp_arena_init:
    mov [rdi + ucmp_arena_t.base_ptr], rsi
    mov [rdi + ucmp_arena_t.capacity], rdx
    mov qword [rdi + ucmp_arena_t.offset], 0
    ret

; -----------------------------------------------------------------------------
; ucmp_arena_alloc
;
; Inputs:
;   RDI = Pointer to ucmp_arena_t state structure
;   RSI = Bytes to allocate
;
; Returns:
;   RAX = Address of allocated memory (or NULL 0 if capacity exceeded)
; -----------------------------------------------------------------------------
align 32
ucmp_arena_alloc:
    mov rax, [rdi + ucmp_arena_t.offset]
    mov rdx, rax
    add rdx, rsi                     ; RDX = new_offset

    cmp rdx, [rdi + ucmp_arena_t.capacity]
    jg .out_of_mem

    mov [rdi + ucmp_arena_t.offset], rdx
    add rax, [rdi + ucmp_arena_t.base_ptr]
    ret

.out_of_mem:
    xor rax, rax
    ret

; -----------------------------------------------------------------------------
; ucmp_arena_reset
;
; Resets allocation offset back to zero.
; -----------------------------------------------------------------------------
align 32
ucmp_arena_reset:
    mov qword [rdi + ucmp_arena_t.offset], 0
    ret
