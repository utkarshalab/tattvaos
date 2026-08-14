; =============================================================================
; lib/io/dma/alloc.asm
; Coherent contiguous DMA physical/virtual memory allocator.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_DMA_ALLOC_ASM
%define IO_DMA_ALLOC_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"
%include "lib/io/io.inc"
%include "lib/io/error/codes.asm"

section .data
global dma_virtual_alloc_ptr
dma_virtual_alloc_ptr: dq 0x8000000000  ; Base virtual address for DMA allocations

section .text

; Allocated in lib/mem

; =============================================================================
; dma_alloc — Allocate DMA-coherent, physically contiguous memory.
; In : RDI = Size in bytes
;      RSI = Alignment (power of 2, minimum 64 bytes)
;      RDX = Flags (DMA_32BIT = 0x01, DMA_HUGEPAGE = 0x02)
; Out: RAX = Physical address of the allocated buffer (or negative error code)
;      RBX = Virtual address of the allocated buffer (or 0)
; RSO: RAX and RBX owned-out
; =============================================================================
IO_FUNC dma_alloc
    guard_bar rsi, 64, 4194304      ; Check alignment bounds [64, 4MB]
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r12
    push    r13
    push    r14
    push    r15

    mov     r12, rdi                ; R12 = size in bytes
    mov     r13, rsi                ; R13 = alignment
    mov     r14, rdx                ; R14 = flags

    ; 1. Round size up to multiple of 4KB pages
    mov     rax, r12
    add     rax, 4095
    shr     rax, 12                 ; RAX = Page count
    mov     r15, rax                ; R15 = Page count

    ; 2. Allocate physical contiguous pages
    mov     rdi, r15                ; RDI = page count
    call    rt_reserve_alloc
    test    rax, rax
    jz      .err_nomem

    mov     rbx, rax                ; RBX = physical base address

    ; Check 32-bit DMA limit if flagged
    test    r14, 0x01               ; DMA_32BIT flag
    jz      .map_virtual
    mov     rcx, rbx
    add     rcx, r12                ; RCX = end physical address
    cmp     rcx, 0x100000000        ; Check if it exceeds 4GB
    jae     .err_nomem              ; Physically allocated above 4GB, fail

.map_virtual:
    ; 3. Reserve virtual space
    ; Load current virtual pointer, align it, and bump it
    mov     rax, [rel dma_virtual_alloc_ptr]
    mov     rcx, r13                ; alignment
    dec     rcx                     ; mask = alignment - 1
    add     rax, rcx
    not     rcx
    and     rax, rcx                ; RAX = aligned virtual base

    mov     r12, rax                ; R12 = aligned virtual base pointer
    mov     rcx, r15
    shl     rcx, 12                 ; RCX = total page sizes
    add     rax, rcx
    mov     [rel dma_virtual_alloc_ptr], rax ; Save bumped virtual pointer

    ; 4. Map pages: virt_map_space(virt_addr, phys_addr, flags, pml4_root)
    xor     r9, r9                  ; R9 = page index iterator

.map_loop:
    cmp     r9, r15
    je      .map_done

    ; Calculate addresses for this page
    mov     rdi, r9
    shl     rdi, 12
    add     rdi, r12                ; RDI = virtual page address

    mov     rsi, r9
    shl     rsi, 12
    add     rsi, rbx                ; RSI = physical page address

    ; Page Table flags: Present (bit 0) | Write (bit 1) | Cache Disable (bit 4 = 0x10 for DMA coherency)
    mov     rdx, 0x13               ; PTE_PRESENT | PTE_WRITE | PTE_PCD
    xor     r8, r8                  ; Use current PML4 CR3
    call    virt_map_space

    inc     r9
    jmp     .map_loop

.map_done:
    ; Return physical base in RAX, virtual base in RBX
    mov     rax, rbx                ; RAX = physical address
    mov     rbx, r12                ; RBX = virtual address
    jmp     .done

.err_nomem:
    mov     rax, IO_ERR_NOMEM
    xor     rbx, rbx

.done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
IO_ENDFUNC dma_alloc

%endif ; IO_DMA_ALLOC_ASM
