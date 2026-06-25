; =============================================================================
; Tattva OS — lib/mem/virt/hardware/zone_movable.asm
; =============================================================================
; Memory Compact Hot-Plug Zones / ZONE_MOVABLE (Feature 4).
; Allows marking specific physical page frame number (PFN) ranges as movable
; by setting the PAGE_MOVABLE bit flag (bit 12) in their page_t descriptors.
; Also manages dynamic page descriptor array allocation.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_HARDWARE_ZONE_MOVABLE_ASM
%define LIB_MEM_VIRT_HARDWARE_ZONE_MOVABLE_ASM

[BITS 64]

; page_t structure definition
struc page_t
    .flags:     resq 1          ; Bit 12 = PAGE_MOVABLE
    .lock:      resq 1          ; Spinlock (0 = free, 1 = locked)
endstruc

section .text

extern pages_array
extern buddy_start_addr
extern buddy_end_addr
extern heap_alloc
extern memzero

; -----------------------------------------------------------------------------
; zone_mark_movable — marks a range of physical frame numbers as movable
; Input:
;   RDI = start_frame_number (PFN)
;   RSI = end_frame_number   (PFN, exclusive)
; Output: none
; Clobbers: RAX, RCX, RDX, RSI, RDI, R8-R11
; -----------------------------------------------------------------------------
global zone_mark_movable
zone_mark_movable:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                    ; R12 = start PFN
    mov r13, rsi                    ; R13 = end PFN

    ; 1. If pages_array is NULL, dynamically allocate it based on node size
    mov rax, [pages_array]
    test rax, rax
    jnz .have_array

    ; Calculate node page count = (buddy_end_addr - buddy_start_addr) / 4096
    mov rax, [buddy_end_addr]
    sub rax, [buddy_start_addr]
    shr rax, 12                     ; RAX = total page count N
    mov r14, rax

    ; Allocate memory for N * page_t_size (16 bytes per descriptor)
    imul rax, 16                    ; RAX = N * 16 bytes
    mov rdi, rax
    call heap_alloc
    test rax, rax
    jz .exit                        ; OOM, exit

    mov [pages_array], rax          ; Store pointer
    mov rbp, rax

    ; Zero out the pages_array using memzero
    mov rdi, rbp
    mov rsi, r14
    imul rsi, 16                    ; size in bytes
    call memzero

.have_array:
    mov rbp, [pages_array]

    ; 2. Loop through all PFNs in [start PFN, end PFN)
    mov r14, r12                    ; R14 = current PFN

.mark_loop:
    cmp r14, r13
    jae .exit

    ; page_descriptor = pages_array + current_PFN * 16
    mov rax, r14
    imul rax, 16                    ; RAX = offset
    lea r15, [rbp + rax]            ; R15 = descriptor pointer

    ; Acquire spinlock for page_t descriptor
.acquire_lock:
    lock bts qword [r15 + page_t.lock], 0
    jc .spin_wait
    jmp .locked
.spin_wait:
    pause
    test qword [r15 + page_t.lock], 1
    jnz .spin_wait
    jmp .acquire_lock

.locked:
    ; Set the PAGE_MOVABLE flag (bit 12)
    mov rax, [r15 + page_t.flags]
    or rax, (1 << 12)
    mov [r15 + page_t.flags], rax

    ; Release lock
    mov qword [r15 + page_t.lock], 0

    inc r14                         ; next PFN
    jmp .mark_loop

.exit:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

section .data

global buddy_alloc_mask
align 8
buddy_alloc_mask: dq 0              ; Allocator mask control (0 = default, 1 = avoid ZONE_MOVABLE)

%endif ; LIB_MEM_VIRT_HARDWARE_ZONE_MOVABLE_ASM
