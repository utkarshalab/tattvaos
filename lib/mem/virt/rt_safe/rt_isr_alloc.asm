; =============================================================================
; Tattva OS — lib/mem/virt/rt_isr_alloc.asm
; =============================================================================
; Interrupt-Safe Lock-Free Memory Allocator — Subfeature 37.4.
;
; Implements a lock-free page allocator designed for interrupt context (ISRs)
; and DMA completion handlers. Sourced from a pre-allocated pool of 16 pages.
; Uses an atomic ring buffer with 'lock cmpxchg' CAS operations to guarantee
; safety without acquiring locks or blocking interrupts.
;
; API:
;   rt_isr_alloc_init()     — Pre-allocates reserve pages and initializes ring.
;   rt_isr_alloc()          — Lock-free page allocate from interrupt context.
;   rt_isr_free(page_addr)  — Lock-free page release back to reserve pool.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_RT_ISR_ALLOC_ASM
%define LIB_MEM_VIRT_RT_ISR_ALLOC_ASM

[BITS 64]

; ---------------------------------------------------------------------------
; Constants
; ---------------------------------------------------------------------------
ISR_RING_SIZE           equ 16      ; 16 pages reserve limit

; ---------------------------------------------------------------------------
section .text

; ---------------------------------------------------------------------------
; rt_isr_alloc_init — Pre-allocate reserve pages and setup ring pointers
; Output: RAX = 1 on success, 0 on failure
; Clobbers: RAX, RCX, RDX, RDI, RSI, R8
; ---------------------------------------------------------------------------
global rt_isr_alloc_init
rt_isr_alloc_init:
    push rbx
    push r12

    mov  qword [sys_rt_isr_head], 0
    mov  qword [sys_rt_isr_tail], 0
    mov  qword [sys_rt_isr_allocations], 0
    mov  qword [sys_rt_isr_freed], 0

    ; Allocate 16 pages from PMM
    xor  r12, r12                   ; R12 = index loop

.alloc_loop:
    call phys_alloc_page
    test rax, rax
    jz   .oom

    ; Store page in ring slot
    mov  [sys_rt_isr_ring + r12 * 8], rax
    inc  r12
    cmp  r12, ISR_RING_SIZE
    jb   .alloc_loop

    ; Setup tail pointer to indicate 16 available items
    mov  qword [sys_rt_isr_tail], ISR_RING_SIZE

    mov  rax, 1
    pop  r12
    pop  rbx
    ret

.oom:
    ; Free allocated pages on error
    test r12, r12
    jz   .fail
    mov  rbx, r12
    xor  r12, r12
.cleanup_loop:
    mov  rdi, [sys_rt_isr_ring + r12 * 8]
    call phys_free_page
    inc  r12
    cmp  r12, rbx
    jb   .cleanup_loop

.fail:
    xor  rax, rax
    pop  r12
    pop  rbx
    ret

; ---------------------------------------------------------------------------
; rt_isr_alloc — Lock-free allocation from interrupt context
; Output: RAX = Physical page address, 0 on failure (ring empty)
; Clobbers: RAX, RCX, RDX, R8, R9
; ---------------------------------------------------------------------------
global rt_isr_alloc
rt_isr_alloc:
    ; Atomic pop loop
.retry:
    mov  rdx, [sys_rt_isr_head]     ; RDX = current head index
    mov  r9, [sys_rt_isr_tail]      ; R9 = current tail index
    cmp  rdx, r9
    je   .empty                     ; head == tail, ring is empty!

    ; Read value at current head slot
    mov  rcx, rdx
    and  rcx, (ISR_RING_SIZE - 1)   ; RCX = index in ring buffer
    mov  r8, [sys_rt_isr_ring + rcx * 8] ; R8 = physical page pointer

    ; Calculate new head candidate index
    lea  rsi, [rdx + 1]

    ; Atomic swap: if head == RDX, set head = rsi
    mov  rax, rdx
    lock cmpxchg [sys_rt_isr_head], rsi
    jnz  .retry                     ; collision detected, retry CAS

    ; Success! Return the physical page base address
    mov  rax, r8
    inc  qword [sys_rt_isr_allocations]
    ret

.empty:
    xor  rax, rax
    ret

; ---------------------------------------------------------------------------
; rt_isr_free — Lock-free return of page to reserve pool
; Input:  RDI = Physical page address
; Output: RAX = 1 on success, 0 on failure (ring full)
; Clobbers: RAX, RCX, RDX, R8, R9
; ---------------------------------------------------------------------------
global rt_isr_free
rt_isr_free:
    test rdi, rdi
    jz   .fail

    mov  r8, rdi                    ; R8 = page address

    ; Atomic push loop
.retry:
    mov  rdx, [sys_rt_isr_tail]     ; RDX = current tail index
    mov  r9, [sys_rt_isr_head]      ; R9 = current head index
    
    ; Check if ring is full: tail - head >= ISR_RING_SIZE
    mov  rcx, rdx
    sub  rcx, r9
    cmp  rcx, ISR_RING_SIZE
    jae  .full

    ; Safe to write to slot at tail, since head cannot reach tail if not full
    mov  rcx, rdx
    and  rcx, (ISR_RING_SIZE - 1)
    mov  [sys_rt_isr_ring + rcx * 8], r8

    ; Increment tail atomically
    lea  rsi, [rdx + 1]
    mov  rax, rdx
    lock cmpxchg [sys_rt_isr_tail], rsi
    jnz  .retry                     ; collision, retry

    ; Success
    inc  qword [sys_rt_isr_freed]
    mov  rax, 1
    ret

.full:
    ; Ring full: we must free page back to main PMM to prevent leak
    call phys_free_page
    inc  qword [sys_rt_isr_freed]
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
global sys_rt_isr_head
sys_rt_isr_head:                dq 0

align 8
global sys_rt_isr_tail
sys_rt_isr_tail:                dq 0

align 8
global sys_rt_isr_allocations
sys_rt_isr_allocations:         dq 0

align 8
global sys_rt_isr_freed
sys_rt_isr_freed:               dq 0

; ---------------------------------------------------------------------------
; BSS — Ring buffer array
; ---------------------------------------------------------------------------
section .bss

alignb 64
sys_rt_isr_ring:                resq ISR_RING_SIZE

section .text

%endif ; LIB_MEM_VIRT_RT_ISR_ALLOC_ASM
