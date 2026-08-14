; =============================================================================
; Tattva OS — lib/mem/virt/paging/khugepaged.asm
; =============================================================================
; Dynamic Transparent Huge Page (THP) Coalescing / khugepaged (Feature 7).
; Consolidates 512 scattered contiguous-content 4KB pages into a single 2MB huge page.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_PAGING_KHUGEPAGED_ASM
%define LIB_MEM_VIRT_PAGING_KHUGEPAGED_ASM

[BITS 64]

section .text


; -----------------------------------------------------------------------------
; khugepaged_scan_and_collapse — coalesces 512 scattered 4KB pages into a 2MB page
; Input:
;   RDI = start_vaddr (Virtual address of region, 2MB aligned)
; Output:
;   RAX = 1 on success, 0 on failure
; Clobbers: RAX, RCX, RDX, RSI, RDI, R8-R11
; -----------------------------------------------------------------------------
global khugepaged_scan_and_collapse
khugepaged_scan_and_collapse:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15

    mov r14, rdi                    ; R14 = start_vaddr (2MB aligned virtual address)

    ; 1. Walk current PML4 hierarchy (CR3) to locate PMD entry
    mov rdx, cr3
    and rdx, 0xFFFFFFFFFFFFF000     ; RDX = PML4 physical base (identity mapped virtual)
    
    ; PML4 Index
    mov rax, r14
    shr rax, 39
    and rax, 0x1FF                  ; RAX = logical PML4 index
    lea rcx, [pml4_shuffle_map]
    movzx rax, word [rcx + rax * 2]  ; RAX = physical index
    
    mov rbx, [rdx + rax * 8]        ; RBX = PML4 entry
    test rbx, 0x01                  ; Present?
    jz .fail
    
    ; PDPT Index
    and rbx, 0xFFFFFFFFFFFFF000      ; RBX = PDPT virtual base
    mov rax, r14
    shr rax, 30
    and rax, 0x1FF                  ; RAX = PDPT index
    mov rdx, [rbx + rax * 8]        ; RDX = PDPT entry
    test rdx, 0x01                  ; Present?
    jz .fail
    test rdx, 0x80                  ; Huge page (1GB)? Skip.
    jnz .fail
    
    ; PD (PMD) Index
    and rdx, 0xFFFFFFFFFFFFF000      ; RDX = PD virtual base
    mov rax, r14
    shr rax, 21
    and rax, 0x1FF                  ; RAX = PD index
    lea r12, [rdx + rax * 8]        ; R12 = pointer to target PMD entry (PDE)
    mov rsi, [r12]                  ; RSI = PMD entry value
    test rsi, 0x01                  ; Present?
    jz .fail
    test rsi, 0x80                  ; Already huge page (2MB)? Skip.
    jnz .fail
    
    ; R15 = PT base virtual pointer (identity mapped physical pointer)
    and rsi, 0xFFFFFFFFFFFFF000
    mov r15, rsi

    ; 2. Read Reference Entry 0 and extract reference flags
    mov rbp, [r15 + 0]
    test rbp, 0x01                  ; Present?
    jz .fail

    ; Mask physical frame address (bits 12-51) out of RBP to keep only attribute flags
    mov rax, 0x000FFFFFFFFFF000
    not rax                         ; RAX = attribute mask
    and rbp, rax                    ; RBP = reference flags

    ; 3. Verify all 512 entries are Present and possess matching flags
    xor rbx, rbx                    ; RBX = entry index (0 to 511)
.scan_pt:
    cmp rbx, 512
    jge .scan_ok
    
    mov r8, [r15 + rbx * 8]
    test r8, 0x01                  ; Present?
    jz .fail
    
    mov rdx, r8
    and rdx, rax                    ; RDX = current flags
    cmp rdx, rbp
    jne .fail                      ; Flags mismatch, abort coalescing
    
    inc rbx
    jmp .scan_pt

.scan_ok:
    ; 4. Allocate a 2MB physical contiguous page frame from the Buddy Allocator (Order 9)
    mov rdi, 9                      ; Order 9 (512 contiguous pages)
    call buddy_alloc                ; RAX = new physical address
    test rax, rax
    jz .fail
    mov r13, rax                    ; R13 = physical base address of new huge page

    ; 5. Write-protect the 512 source pages and flush their TLB lines
    xor rbx, rbx
.wp_loop:
    cmp rbx, 512
    jge .wp_done
    
    and qword [r15 + rbx * 8], ~0x02 ; Clear Writable (bit 1)
    
    ; Virtual address of this page = start_vaddr (R14) + rbx * 4096
    mov rdx, rbx
    shl rdx, 12
    add rdx, r14
    invlpg [rdx]                    ; Invalidate TLB line
    
    inc rbx
    jmp .wp_loop
.wp_done:

    ; 6. Copy data from the 512 scattered physical frames to the new 2MB page
    xor rbx, rbx
.copy_loop:
    cmp rbx, 512
    jge .copy_done
    
    mov rsi, [r15 + rbx * 8]
    and rsi, 0xFFFFFFFFFFFFF000     ; RSI = source physical pointer

    mov rdi, r13
    mov rax, rbx
    shl rax, 12
    add rdi, rax                    ; RDI = destination physical pointer

    ; Copy 4096 bytes (512 quadwords)
    mov rcx, 512
    cld
    rep movsq

    inc rbx
    jmp .copy_loop
.copy_done:

    ; 7. Atomically write the physical address of the 2MB page into target PMD entry
    ; PMD entry = physical base | reference flags | PAGE_HUGE (bit 7)
    mov rax, r13
    or rax, rbp
    or rax, 0x80                    ; Huge page (bit 7)
    
    lock xchg [r12], rax            ; Clear/write PMD entry, RAX = physical address of old PT page
    and rax, 0xFFFFFFFFFFFFF000     ; Mask off attribute/flag bits to get the clean physical address
    mov r15, rax                    ; R15 = old PT page (no longer needed for copy)

    ; 8. Flush TLB range for the collapsed 2MB virtual address range
    xor rbx, rbx
.tlb_loop:
    cmp rbx, 512
    jge .tlb_done
    mov rdx, rbx
    shl rdx, 12
    add rdx, r14
    invlpg [rdx]
    inc rbx
    jmp .tlb_loop
.tlb_done:

    ; 9. Free the 512 scattered original 4KB frames
    xor rbx, rbx
.free_pages_loop:
    cmp rbx, 512
    jge .free_pages_done
    
    mov rdi, [r15 + rbx * 8]
    and rdi, 0xFFFFFFFFFFFFF000
    test rdi, rdi
    jz .skip_free
    
    ; phys_free_page is clobber-safe for our non-volatile state (RBX, R15, R14)
    call phys_free_page
.skip_free:
    inc rbx
    jmp .free_pages_loop
.free_pages_done:

    ; 10. Free the old PT page directory page
    mov rdi, r15
    call phys_free_page

    mov rax, 1                      ; Success
    jmp .exit

.fail:
    xor rax, rax                    ; Failure

.exit:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

%endif ; LIB_MEM_VIRT_PAGING_KHUGEPAGED_ASM
