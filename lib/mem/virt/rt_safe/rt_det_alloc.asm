%ifndef GUARD_LIB_MEM_VIRT_RT_SAFE_RT_DET_ALLOC_ASM
%define GUARD_LIB_MEM_VIRT_RT_SAFE_RT_DET_ALLOC_ASM
; =============================================================================
; Tattva OS — lib/mem/virt/rt_det_alloc.asm
; =============================================================================
; Deterministic Memory Allocator — Subfeature 37.3.
;
; Implements a TLSF-like (Two-Level Segregated Fit) real-time allocator.
; Uses 8 segregated size classes (16B to 2048B) and a first-level availability
; bitmap to guarantee strict O(1) worst-case bounded execution time for
; allocations and frees, eliminating unbounded list-walking overhead.
;
; Block Header Layout:
;   0: next_free_block      — dq: pointer to next block in list
;   8: block_size           — dq: size of this block
;  16: in_use               — dq: 1 if active, 0 if free
;
; Size Classes:
;   Class 0: 16 bytes
;   Class 1: 32 bytes
;   Class 2: 64 bytes
;   Class 3: 128 bytes
;   Class 4: 256 bytes
;   Class 5: 512 bytes
;   Class 6: 1024 bytes
;   Class 7: 2048 bytes
;
; API:
;   rt_det_alloc_init(addr, size)   — Initialize the allocator pool context.
;   rt_det_alloc(size)              — Bounded-time allocation (O(1)).
;   rt_det_free(ptr)                — Bounded-time free (O(1)).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_RT_DET_ALLOC_ASM
%define LIB_MEM_VIRT_RT_DET_ALLOC_ASM

[BITS 64]

; ---------------------------------------------------------------------------
; Block Header offsets
; ---------------------------------------------------------------------------
BLOCK_NEXT_OFF          equ 0       ; dq: next free pointer
BLOCK_SIZE_OFF          equ 8       ; dq: size in bytes
BLOCK_INUSE_OFF         equ 16      ; dq: in_use flag
BLOCK_HEADER_SIZE       equ 24

; ---------------------------------------------------------------------------
section .text

; ---------------------------------------------------------------------------
; rt_det_alloc_init — Initialize the deterministic pool
; Input:
;   RDI = Pool memory start address
;   RSI = Total pool size in bytes
; Output: RAX = 1
; Clobbers: RAX, RCX, RDI
; ---------------------------------------------------------------------------
global rt_det_alloc_init
rt_det_alloc_init:
    push rdi
    push rcx

    mov  [sys_rt_pool_start], rdi
    mov  [sys_rt_pool_size], rsi
    
    ; Data/Bumper allocator starts after metadata
    mov  rax, rdi
    add  rax, rsi
    mov  [sys_rt_pool_end], rax

    ; Setup bumper pointer
    mov  [sys_rt_pool_bump], rdi

    ; Clear free lists heads (8 * 8 = 64 bytes)
    lea  rdi, [sys_rt_free_lists]
    xor  rax, rax
    mov  rcx, 8
    rep  stosq

    ; Clear bitmap & counters
    mov  qword [sys_rt_first_level_bitmap], 0
    mov  qword [sys_rt_det_allocated_bytes], 0
    mov  qword [sys_rt_det_free_blocks], 0

    mov  rax, 1
    pop  rcx
    pop  rdi
    ret

; ---------------------------------------------------------------------------
; rt_det_alloc — Allocate a block with worst-case O(1) time
; Input:  RDI = requested size
; Output: RAX = address of allocated block data, or 0 if OOM
; Clobbers: RAX, RBX, RCX, RDX, R8, R9, R10
; ---------------------------------------------------------------------------
global rt_det_alloc
rt_det_alloc:
    test rdi, rdi
    jz   .fail

    mov  r8, rdi                    ; R8 = requested size

    ; 1. Map requested size to class index (0 to 7)
    ; Sizes map: 16 -> 0, 32 -> 1, 64 -> 2, 128 -> 3, 256 -> 4, 512 -> 5, 1024 -> 6, 2048 -> 7
    xor  r9, r9                     ; R9 = class index
    mov  r10, 16                    ; R10 = size limit for class 0
.map_class_loop:
    cmp  r8, r10
    jbe  .class_found
    shl  r10, 1                     ; next class limit
    inc  r9
    cmp  r9, 7
    jb   .map_class_loop
    ; Caps at class 7 (2048 bytes)

.class_found:
    ; Class index is in R9, Class size is in R10.
    
    ; 2. Scan availability bitmap starting at class R9
    ; We construct a mask of bits >= R9
    mov  rcx, r9
    mov  rax, 0xFF
    shl  rax, cl                    ; RAX = mask of bits >= index
    and  al, byte [sys_rt_first_level_bitmap] ; apply mask to active bitmap
    
    test al, al
    jz   .use_bumper_alloc          ; no free block of sufficient size

    ; Find first non-empty class (least significant set bit in masked bitmap)
    bsf  rcx, rax                   ; RCX = index of best-fit class (O(1))

    ; 3. Pop block from free list class RCX
    lea  rdx, [sys_rt_free_lists + rcx * 8]
    mov  rbx, [rdx]                 ; RBX = pointer to header of free block
    
    ; Unlink from list
    mov  rax, [rbx + BLOCK_NEXT_OFF]
    mov  [rdx], rax                 ; head = block->next
    
    ; If list became empty, clear bit in bitmap
    test rax, rax
    jnz  .block_popped
    btr  qword [sys_rt_first_level_bitmap], rcx

.block_popped:
    dec  qword [sys_rt_det_free_blocks]
    
    ; Mark block as in-use
    mov  qword [rbx + BLOCK_INUSE_OFF], 1
    
    ; Retrieve block size
    mov  rsi, [rbx + BLOCK_SIZE_OFF]
    add  [sys_rt_det_allocated_bytes], rsi

    ; Return address after header
    lea  rax, [rbx + BLOCK_HEADER_SIZE]
    ret

.use_bumper_alloc:
    ; Allocates from pool bump pointer
    mov  rax, [sys_rt_pool_bump]
    
    ; Calculate total size needed = requested class size + header size
    mov  rdx, r10                   ; Class size (R10)
    add  rdx, BLOCK_HEADER_SIZE
    
    mov  rcx, rax
    add  rcx, rdx                   ; RCX = potential new bump pointer
    
    cmp  rcx, [sys_rt_pool_end]
    ja   .fail                      ; Pool OOM!

    ; Write header
    mov  qword [rax + BLOCK_NEXT_OFF], 0
    mov  [rax + BLOCK_SIZE_OFF], r10 ; store class size (R10)
    mov  qword [rax + BLOCK_INUSE_OFF], 1

    ; Update bump pointer
    mov  [sys_rt_pool_bump], rcx

    add  [sys_rt_det_allocated_bytes], r10

    ; Return pointer after header
    add  rax, BLOCK_HEADER_SIZE
    ret

.fail:
    xor  rax, rax
    ret

; ---------------------------------------------------------------------------
; rt_det_free — Free a block back to the segregated lists in O(1) time
; Input:  RDI = address of block data (returned by rt_det_alloc)
; Output: RAX = 1 on success, 0 on failure
; Clobbers: RAX, RBX, RCX, RDX, R8, R9
; ---------------------------------------------------------------------------
global rt_det_free
rt_det_free:
    test rdi, rdi
    jz   .fail

    ; Backtrack to header
    sub  rdi, BLOCK_HEADER_SIZE     ; RDI = block header address

    ; Verify block is currently marked in-use (double free protection)
    cmp  qword [rdi + BLOCK_INUSE_OFF], 1
    jne  .fail

    ; Retrieve block size
    mov  rbx, [rdi + BLOCK_SIZE_OFF]

    ; Determine class index from size
    xor  r8, r8                     ; R8 = class index
    mov  r9, 16                     ; limit
.map_free_class:
    cmp  rbx, r9
    jbe  .free_class_found
    shl  r9, 1
    inc  r8
    cmp  r8, 7
    jb   .map_free_class

.free_class_found:
    ; R8 = target class index

    ; Mark block as free
    mov  qword [rdi + BLOCK_INUSE_OFF], 0
    sub  [sys_rt_det_allocated_bytes], rbx

    ; Link to head of free list R8
    lea  rcx, [sys_rt_free_lists + r8 * 8]
    mov  rax, [rcx]                 ; RAX = current head
    mov  [rdi + BLOCK_NEXT_OFF], rax ; block->next = current head
    mov  [rcx], rdi                 ; head = block

    ; Set bit in first-level bitmap
    bts  qword [sys_rt_first_level_bitmap], r8

    inc  qword [sys_rt_det_free_blocks]
    mov  rax, 1
    ret

.fail:
    xor  rax, rax
    ret

; ---------------------------------------------------------------------------
; Data
; ---------------------------------------------------------------------------
section .data

align 8
sys_rt_pool_start:              dq 0
align 8
sys_rt_pool_size:               dq 0
align 8
sys_rt_pool_end:                dq 0
align 8
sys_rt_pool_bump:               dq 0

align 8
global sys_rt_det_allocated_bytes
sys_rt_det_allocated_bytes:     dq 0

align 8
global sys_rt_det_free_blocks
sys_rt_det_free_blocks:         dq 0

align 8
sys_rt_first_level_bitmap:      dq 0

; ---------------------------------------------------------------------------
; BSS — Free lists heads (8 lists)
; ---------------------------------------------------------------------------
section .bss

alignb 64
sys_rt_free_lists:              resq 8

section .text

%endif ; LIB_MEM_VIRT_RT_DET_ALLOC_ASM

%endif ; GUARD_LIB_MEM_VIRT_RT_SAFE_RT_DET_ALLOC_ASM
