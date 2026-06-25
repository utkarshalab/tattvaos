; =============================================================================
; Tattva OS — lib/mem/virt/profile/damon.asm
; =============================================================================
; Access Monitoring Engine (DAMON-equivalent) (Feature 25).
; Audits page access frequency using standard page table Accessed bit queries.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_PROFILE_DAMON_ASM
%define LIB_MEM_VIRT_PROFILE_DAMON_ASM

[BITS 64]

; DAMON region structure definition
struc damon_region_t
    .start_vaddr:   resq 1
    .end_vaddr:     resq 1
    .access_count:  resq 1
endstruc

; -----------------------------------------------------------------------------
; Section .text
; -----------------------------------------------------------------------------
section .text

extern virt_walk_table

; -----------------------------------------------------------------------------
; damon_register_region — adds a range to the monitoring engine
; Input:
;   RDI = start_vaddr (page aligned virtual address)
;   RSI = end_vaddr   (page aligned exclusive virtual address)
; Output:
;   RAX = 1 on success, 0 on failure (table overflow)
; Clobbers: RAX, RCX
; -----------------------------------------------------------------------------
global damon_register_region
damon_register_region:
    mov rcx, [damon_region_count]
    cmp rcx, 32
    jae .fail                       ; capacity reached (32 slots)

    ; Calculate target slot address
    mov rax, rcx
    imul rax, damon_region_t_size
    lea rax, [damon_regions + rax]

    mov [rax + damon_region_t.start_vaddr], rdi
    mov [rax + damon_region_t.end_vaddr], rsi
    mov qword [rax + damon_region_t.access_count], 0

    inc qword [damon_region_count]
    mov rax, 1
    ret

.fail:
    xor rax, rax
    ret

; -----------------------------------------------------------------------------
; damon_sample_accesses — queries and clears Accessed bits in page table entries
; Input:  None
; Output: None
; Clobbers: RAX, RCX, RDX, RSI, RDI, R8-R11
; -----------------------------------------------------------------------------
global damon_sample_accesses
damon_sample_accesses:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp

    mov r13, [damon_region_count]
    test r13, r13
    jz .done

    xor r12, r12                    ; R12 = current region index = 0

.region_loop:
    cmp r12, r13
    jae .done

    ; Get pointer to current region
    mov rax, r12
    imul rax, damon_region_t_size
    lea r14, [damon_regions + rax]  ; R14 = current region descriptor

    mov r15, [r14 + damon_region_t.start_vaddr]
    mov rbx, [r14 + damon_region_t.end_vaddr]
    xor rbp, rbp                    ; RBP = accessed_flag = 0

.page_loop:
    cmp r15, rbx
    jae .region_end

    ; Walk page tables to locate leaf PTE
    mov rdi, r15
    mov rsi, 0                      ; active CR3
    call virt_walk_table            ; RAX = leaf PTE, RDX = level
    test rax, rax
    jz .skip_page

    mov rcx, [rax]
    test rcx, 1                     ; Present?
    jz .skip_page

    test rcx, 0x20                  ; bit 5 = PAGE_ACCESSED
    jz .skip_page

    ; Accessed bit is set. Clear Accessed bit in PTE
    and qword [rax], ~0x20
    invlpg [r15]                    ; invalidate TLB for this page virtual address
    mov rbp, 1                      ; Set region accessed flag to 1

.skip_page:
    add r15, 4096                   ; move to next page
    jmp .page_loop

.region_end:
    ; Update rolling decay profile count
    test rbp, rbp
    jz .decay

    inc qword [r14 + damon_region_t.access_count]
    jmp .next_region

.decay:
    mov rax, [r14 + damon_region_t.access_count]
    test rax, rax
    jz .next_region                 ; clamp to 0 to prevent underflow
    dec rax
    mov [r14 + damon_region_t.access_count], rax

.next_region:
    inc r12
    jmp .region_loop

.done:
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; Section .data
; -----------------------------------------------------------------------------
section .data

align 8
global damon_region_count
damon_region_count: dq 0

; -----------------------------------------------------------------------------
; Section .bss
; -----------------------------------------------------------------------------
section .bss

align 32
global damon_regions
damon_regions: resb 32 * damon_region_t_size

section .text

%endif ; LIB_MEM_VIRT_PROFILE_DAMON_ASM
