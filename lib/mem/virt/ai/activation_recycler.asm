; =============================================================================
; Tattva OS — lib/mem/virt/activation_recycler.asm
; =============================================================================
; Activation Memory Recycler — Subfeature 36.4.
;
; Manages the reuse of activation memory buffers between neural network layers.
; Maps the same physical frames to different layer-specific virtual addresses,
; avoiding physical memory allocation/deallocation overhead during hot-path
; inference execution.
;
; API:
;   activation_recycler_init()          — Initialize variables.
;   activation_recycler_register(pages) — Allocate backing physical frames.
;   activation_recycler_map(layer, vaddr)— Map physical frames to layer virtual.
;   activation_recycler_unmap(vaddr)    — Unmap layer virtual address.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_ACTIVATION_RECYCLER_ASM
%define LIB_MEM_VIRT_ACTIVATION_RECYCLER_ASM

[BITS 64]

; ---------------------------------------------------------------------------
; Constants
; ---------------------------------------------------------------------------
ACTIVATION_MAX_PAGES equ 256

; ---------------------------------------------------------------------------
section .text

; ---------------------------------------------------------------------------
; activation_recycler_init — Initialize the recycler
; Output: RAX = 1
; Clobbers: RAX, RCX, RDI
; ---------------------------------------------------------------------------
global activation_recycler_init
activation_recycler_init:
    push rdi
    push rcx

    mov  qword [sys_activation_page_count], 0
    mov  qword [sys_activation_mapped_buffers], 0

    ; Zero physical pages table: 256 entries * 8 bytes = 2048 bytes
    lea  rdi, [sys_activation_phys_pages]
    xor  rax, rax
    mov  rcx, ACTIVATION_MAX_PAGES
    rep  stosq

    mov  rax, 1
    pop  rcx
    pop  rdi
    ret

; ---------------------------------------------------------------------------
; activation_recycler_register — Allocate physical frame list for activations
; Input:  RDI = page count to pre-allocate
; Output: RAX = count of successfully allocated pages, 0 on failure
; Clobbers: RAX, RCX, RDX, RDI, RSI, R8
; ---------------------------------------------------------------------------
global activation_recycler_register
activation_recycler_register:
    test rdi, rdi
    jz   .fail
    cmp  rdi, ACTIVATION_MAX_PAGES
    ja   .fail

    mov  r8, rdi                    ; R8 = requested page count
    xor  rcx, rcx                   ; RCX = index loop
    extern phys_alloc_page

.alloc_loop:
    push rcx
    push r8
    call phys_alloc_page            ; RAX = physical page address (4KB aligned)
    pop  r8
    pop  rcx
    test rax, rax
    jz   .oom                       ; Out of physical memory!

    mov  [sys_activation_phys_pages + rcx * 8], rax
    inc  rcx
    cmp  rcx, r8
    jb   .alloc_loop

    mov  [sys_activation_page_count], r8
    mov  rax, r8
    ret

.oom:
    ; Free whatever was allocated so far to prevent leaks
    test rcx, rcx
    jz   .fail
    mov  r8, rcx                    ; R8 = number to free
    xor  rcx, rcx
    extern phys_free_page
.free_loop:
    mov  rdi, [sys_activation_phys_pages + rcx * 8]
    push rcx
    push r8
    call phys_free_page
    pop  r8
    pop  rcx
    mov  qword [sys_activation_phys_pages + rcx * 8], 0
    inc  rcx
    cmp  rcx, r8
    jb   .free_loop

.fail:
    xor  rax, rax
    ret

; ---------------------------------------------------------------------------
; activation_recycler_map — Map the registered physical pages to layer virtual address
; Input:
;   RDI = Layer ID (non-zero)
;   RSI = Virtual Address (4KB page-aligned)
; Output: RAX = 1 on success, 0 on failure
; Clobbers: RAX, RBX, RCX, RDX, RDI, RSI, R8, R9, R10
; ---------------------------------------------------------------------------
global activation_recycler_map
activation_recycler_map:
    test rdi, rdi
    jz   .fail
    test rsi, rsi
    jz   .fail

    mov  r8, [sys_activation_page_count]
    test r8, r8
    jz   .fail                      ; no physical pages registered

    mov  r9, rsi                    ; R9 = base virtual address
    xor  rcx, rcx                   ; RCX = index loop
    extern virt_map

.map_loop:
    ; Calculate virtual address for this page
    mov  rax, rcx
    shl  rax, 12                    ; index * 4096
    add  rax, r9                    ; RAX = target virtual address

    mov  rbx, [sys_activation_phys_pages + rcx * 8] ; RBX = target physical address

    push rcx
    push r8
    push r9
    
    ; virt_map(RDI=vaddr, RSI=paddr, RDX=flags)
    mov  rdi, rax
    mov  rsi, rbx
    mov  rdx, (PAGE_WRITABLE | PAGE_NX)
    call virt_map
    
    pop  r9
    pop  r8
    pop  rcx
    test rax, rax
    jz   .fail_unmap                ; OOM in page table allocation

    inc  rcx
    cmp  rcx, r8
    jb   .map_loop

    inc  qword [sys_activation_mapped_buffers]
    mov  rax, 1
    ret

.fail_unmap:
    ; Clean up partial mappings
    test rcx, rcx
    jz   .fail
    mov  r8, rcx
    xor  rcx, rcx
    extern virt_unmap
.unmap_cleanup:
    mov  rax, rcx
    shl  rax, 12
    add  rax, r9                    ; virtual address to unmap
    
    push rcx
    push r8
    push r9
    mov  rdi, rax
    call virt_unmap
    pop  r9
    pop  r8
    pop  rcx
    
    inc  rcx
    cmp  rcx, r8
    jb   .unmap_cleanup

.fail:
    xor  rax, rax
    ret

; ---------------------------------------------------------------------------
; activation_recycler_unmap — Unmap the virtual address of a layer
; Input:
;   RDI = Virtual Address (base)
; Output: RAX = 1
; Clobbers: RAX, RCX, RDI, RSI, R8
; ---------------------------------------------------------------------------
global activation_recycler_unmap
activation_recycler_unmap:
    test rdi, rdi
    jz   .fail

    mov  r8, [sys_activation_page_count]
    test r8, r8
    jz   .fail

    mov  rsi, rdi                    ; RSI = base virtual address
    xor  rcx, rcx                   ; RCX = index loop
    extern virt_unmap

.unmap_loop:
    mov  rax, rcx
    shl  rax, 12
    add  rax, rsi                   ; virtual address

    push rcx
    push rsi
    push r8
    mov  rdi, rax
    call virt_unmap
    pop  r8
    pop  rsi
    pop  rcx

    inc  rcx
    cmp  rcx, r8
    jb   .unmap_loop

    dec  qword [sys_activation_mapped_buffers]
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
global sys_activation_page_count
sys_activation_page_count:      dq 0

align 8
global sys_activation_mapped_buffers
sys_activation_mapped_buffers:  dq 0

; ---------------------------------------------------------------------------
; BSS
; ---------------------------------------------------------------------------
section .bss

align 64
sys_activation_phys_pages:      resq ACTIVATION_MAX_PAGES

section .text

%endif ; LIB_MEM_VIRT_ACTIVATION_RECYCLER_ASM
