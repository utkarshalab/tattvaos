; =============================================================================
; Tattva OS — lib/mem/virt/paging/pgtable_reap.asm
; =============================================================================
; Intermediate Page Table Reaping (Feature 2).
; Scans the paging hierarchy of a PML4 and reclaims any level-1 page tables (PT)
; that are completely empty (no mapped virtual pages).
; Bypasses pages registered as shared in shared_dir_table to maintain isolation.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_PGTABLE_REAP_ASM
%define LIB_MEM_VIRT_PGTABLE_REAP_ASM

[BITS 64]

; Shared directory descriptor offsets (from pgtable_share.asm)
%ifndef SHARED_DIR_DESC_T_OFFSETS
%define SHARED_DIR_DESC_T_OFFSETS
shared_dir_desc_t.phys_addr equ 0
shared_dir_desc_t.ref_count equ 8
shared_dir_desc_t.lock     equ 16
shared_dir_desc_t_size     equ 24
%endif

section .text

extern pml4_shuffle_map
extern shared_dir_table
extern phys_free_page

; -----------------------------------------------------------------------------
; virt_reap_empty_page_tables — reclaims empty level-1 page tables
; Input:
;   RDI = pml4_base_vaddr (Virtual pointer to PML4 table)
; Output:
;   RAX = reclaimed_page_count
; Clobbers: RAX, RCX, RDX, RSI, RDI, R8-R11
; -----------------------------------------------------------------------------
global virt_reap_empty_page_tables
virt_reap_empty_page_tables:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp

    mov r12, rdi                    ; R12 = PML4 base virtual address
    xor r13, r13                    ; R13 = reclaimed page accumulator
    xor r14, r14                    ; R14 = logical PML4 index (0 to 511)

.pml4_loop:
    cmp r14, 512
    jge .done

    ; Resolve shuffled PML4 index
    lea rcx, [pml4_shuffle_map]
    movzx rax, word [rcx + r14 * 2]  ; RAX = physical index
    
    mov rbx, [r12 + rax * 8]        ; RBX = PML4 Entry
    test rbx, 0x01                  ; Present?
    jz .next_pml4

    ; R15 = PDPT physical address (identity mapped)
    and rbx, 0xFFFFFFFFFFFFF000     ; R15 = PDPT virtual address pointer
    mov r15, rbx
    xor rbp, rbp                    ; RBP = PDPT index (0 to 511)

.pdpt_loop:
    cmp rbp, 512
    jge .next_pml4

    mov rbx, [r15 + rbp * 8]        ; RBX = PDPT entry
    test rbx, 0x01                  ; Present?
    jz .next_pdpt
    test rbx, 0x80                  ; Huge page (1GB)? Skip.
    jnz .next_pdpt

    ; R8 = PD physical address (identity mapped)
    and rbx, 0xFFFFFFFFFFFFF000
    mov r8, rbx
    xor r9, r9                      ; R9 = PD index (0 to 511)

.pd_loop:
    cmp r9, 512
    jge .next_pdpt

    mov rbx, [r8 + r9 * 8]          ; RBX = PD entry
    test rbx, 0x01                  ; Present?
    jz .next_pd
    test rbx, 0x80                  ; Huge page (2MB)? Skip.
    jnz .next_pd

    ; R10 = PT physical address (identity mapped)
    and rbx, 0xFFFFFFFFFFFFF000
    mov r10, rbx

    ; Check if this PT page is actively shared
    mov rdi, r10
    call .is_pt_shared
    test rax, rax
    jnz .next_pd                    ; Skip reaping if shared

    ; Scan all 512 entries in this PT to see if it is empty
    xor rcx, rcx                    ; entry index
    xor rdx, rdx                    ; active entries counter
.scan_pt_loop:
    cmp rcx, 512
    jge .check_empty

    mov rax, [r10 + rcx * 8]
    test rax, 0x401                 ; Check Present (0x01) or Swapped (0x400)
    jz .next_pt_entry
    inc rdx
.next_pt_entry:
    inc rcx
    jmp .scan_pt_loop

.check_empty:
    test rdx, rdx
    jnz .next_pd                    ; Not empty, keep it

    ; PT is empty! Reclaim it atomically
    xor rax, rax
    lock xchg [r8 + r9 * 8], rax    ; Clear PD entry atomically, retrieve old
    
    ; Free the PT physical page (preserve volatile loop registers r8 and r9)
    push r8
    push r9
    mov rdi, r10
    call phys_free_page
    pop r9
    pop r8
    inc r13                         ; Increment reclaimed count

.next_pd:
    inc r9
    jmp .pd_loop

.next_pdpt:
    inc rbp
    jmp .pdpt_loop

.next_pml4:
    inc r14
    jmp .pml4_loop

.done:
    mov rax, r13                    ; Return reclaimed count
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; Helper to check if a PT page is shared (ref_count > 1)
.is_pt_shared:
    lea rdx, [shared_dir_table]
    xor rcx, rcx
.search_loop:
    cmp rcx, 128
    jge .not_shared
    
    lea rax, [rdx + rcx * shared_dir_desc_t_size]
    cmp [rax + shared_dir_desc_t.phys_addr], rdi
    je .found_descriptor
    inc rcx
    jmp .search_loop

.found_descriptor:
    mov rax, [rax + shared_dir_desc_t.ref_count]
    cmp rax, 1
    jg .shared
.not_shared:
    xor rax, rax
    ret
.shared:
    mov rax, 1
    ret

%endif ; LIB_MEM_VIRT_PGTABLE_REAP_ASM
