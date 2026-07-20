; =============================================================================
; Tattva OS — lib/mem/virt/prefetch_alloc.asm
; =============================================================================
; Prefetch-Aware Allocator — Subfeature 36.5.
;
; Allocates weights in cache-line (64-byte) aligned blocks sourced from
; specific NUMA nodes. Implements hardware prefetching routines utilizing
; x86 'prefetcht0' instructions to pre-warm the cache hierarchy for sequential
; model weight scanning.
;
; API:
;   prefetch_alloc_aligned(size, node_id) — Allocates cache-aligned pages from NUMA node.
;   prefetch_alloc_hint(ptr, size)        — Issue prefetcht0 instructions.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_PREFETCH_ALLOC_ASM
%define LIB_MEM_VIRT_PREFETCH_ALLOC_ASM

[BITS 64]

; ---------------------------------------------------------------------------
; Constants
; ---------------------------------------------------------------------------


; ---------------------------------------------------------------------------
section .text

; ---------------------------------------------------------------------------
; prefetch_alloc_aligned — Allocate cache-aligned page blocks on a NUMA node
; Input:
;   RDI = Size in bytes (will be rounded up to multiple of 4KB pages)
;   RSI = NUMA Node ID
; Output: RAX = Virtual address of allocated/mapped block (64-byte aligned), 0 on failure
; Clobbers: RAX, RBX, RCX, RDX, RDI, RSI, R8, R9, R10, R11
; ---------------------------------------------------------------------------
global prefetch_alloc_aligned
prefetch_alloc_aligned:
    test rdi, rdi
    jz   .fail

    mov  r8, rdi                    ; R8 = requested size
    mov  r9, rsi                    ; R9 = NUMA node ID

    ; Calculate pages needed = (size + 4095) / 4096
    mov  rax, r8
    add  rax, 4095
    shr  rax, 12                    ; RAX = page count
    test rax, rax
    jz   .fail
    mov  r10, rax                   ; R10 = page count

    ; Check if NUMA support is available
    ; In Tattva OS: we can call phys_alloc_pages_node if present,
    ; otherwise fallback to global phys_alloc_page.
    ; Let's dynamically call phys_alloc_pages_node (extern numa page allocator)
    extern phys_alloc_pages_node
    
    mov  rdi, r9                    ; NUMA node ID
    mov  rsi, r10                   ; Page count
    call phys_alloc_pages_node      ; RAX = physical base of allocated pages
    test rax, rax
    jz   .fail                      ; allocation failed

    mov  r11, rax                   ; R11 = physical base address

    ; Now we need a virtual mapping range.
    ; Let's dynamically create a VMA or reserve virtual pages starting at a high base address:
    ; For simulation, we map to virtual range starting at 0x60000000 (1.5GB mark)
    ; We keep a pointer for virtual allocations: sys_prefetch_vaddr_ptr
    mov  rax, [sys_prefetch_vaddr_ptr]
    test rax, rax
    jnz  .got_vbase
    mov  rax, 0x60000000            ; initial default base
.got_vbase:
    mov  rbx, rax                   ; RBX = virtual base for this allocation

    ; Update sys_prefetch_vaddr_ptr for next allocation: vbase + pages * 4096
    mov  rdx, r10
    shl  rdx, 12
    add  rdx, rax
    mov  [sys_prefetch_vaddr_ptr], rdx

    ; Loop and map pages: virtual (RBX + i*4096) -> physical (R11 + i*4096)
    xor  rcx, rcx                   ; RCX = loop index
    extern virt_map

.map_loop:
    mov  rax, rcx
    shl  rax, 12                    ; offset = i * 4096
    
    mov  rdi, rbx
    add  rdi, rax                   ; RDI = target virtual address
    
    mov  rsi, r11
    add  rsi, rax                   ; RSI = target physical address
    
    mov  rdx, (PAGE_WRITABLE | PAGE_NX)
    
    push rcx
    push rbx
    push r10
    push r11
    call virt_map
    pop  r11
    pop  r10
    pop  rbx
    pop  rcx
    test rax, rax
    jz   .fail                      ; page mapping failure (OOM)

    inc  rcx
    cmp  rcx, r10
    jb   .map_loop

    inc  qword [sys_prefetch_aligned_allocations]
    
    ; Return the aligned virtual base address (RBX)
    mov  rax, rbx
    ret

.fail:
    xor  rax, rax
    ret

; ---------------------------------------------------------------------------
; prefetch_alloc_hint — Warming CPU cache using x86 prefetcht0 instruction
; Input:
;   RDI = Buffer Address (must be non-zero)
;   RSI = Size in bytes
; Output: RAX = 1
; Clobbers: RAX, RCX
; ---------------------------------------------------------------------------
global prefetch_alloc_hint
prefetch_alloc_hint:
    test rdi, rdi
    jz   .exit
    test rsi, rsi
    jz   .exit

    ; Count of 64-byte cache lines = (size + 63) / 64
    mov  rcx, rsi
    add  rcx, 63
    shr  rcx, 6                     ; RCX = number of loops
    
    xor  rax, rax                   ; RAX = current byte offset
.prefetch_loop:
    prefetcht0 [rdi + rax]          ; prefetch data into L1 data cache
    add  rax, 64                    ; advance by cache line size
    loop .prefetch_loop

.exit:
    mov  rax, 1
    ret

; ---------------------------------------------------------------------------
; Data
; ---------------------------------------------------------------------------
section .data

align 8
global sys_prefetch_aligned_allocations
sys_prefetch_aligned_allocations: dq 0

align 8
sys_prefetch_vaddr_ptr:           dq 0x60000000

section .text

%endif ; LIB_MEM_VIRT_PREFETCH_ALLOC_ASM
