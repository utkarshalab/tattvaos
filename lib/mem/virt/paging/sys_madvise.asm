; =============================================================================
; Tattva OS — lib/mem/virt/paging/sys_madvise.asm
; =============================================================================
; User-Space Allocator Directives / Advanced madvise Support (Feature 8).
; Allows applications to specify memory paging strategies like releasing physical
; ranges (MADV_DONTNEED) or flagging THP coalescing eligibility (MADV_HUGEPAGE).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_PAGING_SYS_MADVISE_ASM
%define LIB_MEM_VIRT_PAGING_SYS_MADVISE_ASM

[BITS 64]

; madvise constants
MADV_DONTNEED    equ 4
MADV_HUGEPAGE    equ 14
VMA_THP_ELIGIBLE equ (1 << 13)

; VMA layout (from virt.asm)
struc vma_local_t
    .start      resq 1
    .end        resq 1
    .flags      resq 1
    .next       resq 1
endstruc

section .text

extern vma_list_head
extern virt_walk_table
extern phys_free_page

; -----------------------------------------------------------------------------
; sys_madvise — advises the kernel about virtual address ranges
; Input:
;   RDI = vaddr       (virtual address start)
;   RSI = length      (range size in bytes)
;   RDX = advice_flag (madvise advice code)
; Output:
;   RAX = 1 on success, 0 on failure
; Clobbers: RAX, RCX, RDX, RSI, RDI, R8-R11
; -----------------------------------------------------------------------------
global sys_madvise
sys_madvise:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                    ; R12 = vaddr
    mov r13, rsi                    ; R13 = length
    mov r14, rdx                    ; R14 = advice_flag

    ; Page-align vaddr down
    and r12, -4096

    ; Page-align length up
    add r13, 4095
    and r13, -4096

    ; 1. Walk VMA tree to find the matching VMA range
    mov r15, [vma_list_head]        ; R15 = current VMA node
.vma_loop:
    test r15, r15
    jz .fail                        ; No matching VMA found

    mov rbx, [r15 + vma_local_t.start]
    cmp r12, rbx
    jb .next_vma

    mov rbp, [r15 + vma_local_t.end]
    cmp r12, rbp
    jb .found_vma

.next_vma:
    mov r15, [r15 + vma_local_t.next]
    jmp .vma_loop

.found_vma:
    ; 2. Handle Advice Flags
    cmp r14, MADV_DONTNEED
    je .handle_dontneed

    cmp r14, MADV_HUGEPAGE
    je .handle_hugepage
    jmp .fail                       ; Unsupported advice code

.handle_dontneed:
    ; Calculate end virtual address (vaddr + length)
    mov rbp, r12
    add rbp, r13                    ; RBP = end vaddr (exclusive)

.dontneed_loop:
    cmp r12, rbp
    jae .success

    ; Walk page tables to locate PTE pointer for current address r12
    mov rdi, r12
    xor rsi, rsi                    ; Use active CR3
    call virt_walk_table            ; RAX = PTE virtual pointer, RDX = level
    test rax, rax
    jz .skip_page                   ; Page not mapped, skip

    ; Read PTE value
    mov rdx, [rax]
    test rdx, 0x01                  ; Present?
    jz .skip_page

    ; Extract physical base address of page frame
    and rdx, 0xFFFFFFFFFFFFF000     ; RDX = physical frame address

    ; Atomically clear the PTE
    mov qword [rax], 0

    ; Invalidate TLB mapping
    invlpg [r12]

    ; Free the physical page frame
    mov rdi, rdx
    call phys_free_page             ; Clobbers volatile registers but preserves R12, RBP, R15

.skip_page:
    add r12, 4096                   ; Next page
    jmp .dontneed_loop

.handle_hugepage:
    ; Flag VMA as THP eligible
    mov rax, [r15 + vma_local_t.flags]
    or rax, VMA_THP_ELIGIBLE
    mov [r15 + vma_local_t.flags], rax

.success:
    mov rax, 1                      ; Return success
    jmp .exit

.fail:
    xor rax, rax                    ; Return failure

.exit:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

%endif ; LIB_MEM_VIRT_PAGING_SYS_MADVISE_ASM
