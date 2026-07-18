; =============================================================================
; lib/io/intr/vector.asm
; Lockless dynamic interrupt vector allocator.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_INTR_VECTOR_ASM
%define IO_INTR_VECTOR_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"
%include "lib/io/error/codes.asm"

section .bss
global global_vector_bitmap
global_vector_bitmap: resb 32        ; 256 bits to track vectors (32 bytes)

section .text

; =============================================================================
; vector_alloc — Allocate a dynamic interrupt vector in range 0x40 - 0xEF
; In : None
; Out: RAX = Allocated vector number (0x40-0xEF), or negative error code on failure
; RSO: RAX owned-out
; =============================================================================
IO_FUNC vector_alloc
    push    rcx
    push    rdx

    ; We scan the vector range from 0x40 to 0xEF (inclusive)
    mov     rcx, 0x40               ; Start index

.loop:
    ; Perform atomic bit test and set (BTS)
    ; BTS checks the bit at index RCX, sets it to 1, and stores the old bit in CF.
    lock bts [rel global_vector_bitmap], rcx
    jnc     .allocated              ; If CF is 0, the bit was free and we took it!

    inc     rcx
    cmp     rcx, 0xF0               ; Up to 0xEF (0xF0 is excluded)
    jl      .loop

    ; Dynamic vectors are exhausted
    mov     rax, IO_ERR_VEC_LIMIT   ; Return vector limit error
    jmp     .done

.allocated:
    mov     rax, rcx                ; RAX = allocated vector

.done:
    pop     rdx
    pop     rcx
    ret
IO_ENDFUNC vector_alloc

; =============================================================================
; vector_free — Release an allocated dynamic vector
; In : RDI = Vector number to release
; Out: None
; RSO: RDI owned-in
; =============================================================================
IO_FUNC vector_free
    ; Verify that the vector is within the dynamic range [0x40, 0xEF]
    cmp     rdi, 0x40
    jl      .done
    cmp     rdi, 0xEF
    jg      .done

    ; Atomic bit test and reset (BTR) to clear the bit
    lock btr [rel global_vector_bitmap], rdi

.done:
    ret
IO_ENDFUNC vector_free

%endif ; IO_INTR_VECTOR_ASM
