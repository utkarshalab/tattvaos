; =============================================================================
; lib/io/dma/map.asm
; Virtual-to-physical address mapping utilities for DMA.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_DMA_MAP_ASM
%define IO_DMA_MAP_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"
%include "lib/io/io.inc"
%include "lib/io/error/codes.asm"

section .text

extern dma_virtual_alloc_ptr
extern virt_map_space

; =============================================================================
; dma_map_virtual — Map a physically pre-allocated block to kernel virtual space
; In : RDI = Physical address base
;      RSI = Size in bytes
;      RDX = Page attribute flags
; Out: RAX = Physical address mapped
;      RBX = Virtual address allocated
; RSO: RAX and RBX owned-out
; =============================================================================
IO_FUNC dma_map_virtual
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r12
    push    r13
    push    r14
    push    r15

    mov     r12, rdi                ; R12 = physical address base
    mov     r13, rsi                ; R13 = size in bytes
    mov     r14, rdx                ; R14 = page attributes

    ; 1. Calculate page count
    mov     rax, r13
    add     rax, 4095
    shr     rax, 12                 ; RAX = Page count
    mov     r15, rax                ; R15 = Page count

    ; 2. Allocate virtual space (aligned to 4KB)
    mov     rax, [rel dma_virtual_alloc_ptr]
    add     rax, 4095
    and     rax, ~4095              ; Align to page boundary
    mov     rbx, rax                ; RBX = virtual base address

    ; Update virtual allocation pointer
    mov     rcx, r15
    shl     rcx, 12                 ; total bytes
    add     rax, rcx
    mov     [rel dma_virtual_alloc_ptr], rax

    ; 3. Map pages
    xor     r9, r9                  ; Iterator

.map_loop:
    cmp     r9, r15
    je      .map_done

    mov     rdi, r9
    shl     rdi, 12
    add     rdi, rbx                ; RDI = virtual address page

    mov     rsi, r9
    shl     rsi, 12
    add     rsi, r12                ; RSI = physical address page

    mov     rdx, r14                ; RDX = page attributes
    xor     r8, r8                  ; R8 = current CR3
    call    virt_map_space

    inc     r9
    jmp     .map_loop

.map_done:
    mov     rax, r12                ; Return physical address
    ; RBX already contains the virtual base address

    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
IO_ENDFUNC dma_map_virtual

; =============================================================================
; dma_unmap_virtual — Unmap virtual address range (stub)
; In : RDI = Virtual base address
;      RSI = Size in bytes
; Out: None
; =============================================================================
IO_FUNC dma_unmap_virtual
    ; Standard unmapping involves walking page tables and clearing PTE present bit,
    ; followed by TLB invalidation. Stubbed for bring-up.
IO_ENDFUNC dma_unmap_virtual

%endif ; IO_DMA_MAP_ASM
