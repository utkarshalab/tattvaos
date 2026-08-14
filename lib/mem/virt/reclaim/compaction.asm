; =============================================================================
; Tattva OS — lib/mem/virt/reclaim/compaction.asm
; =============================================================================
; Active Memory Compaction (Feature 26).
; Relocates active pages to resolve physical RAM fragmentation.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_RECLAIM_COMPACTION_ASM
%define LIB_MEM_VIRT_RECLAIM_COMPACTION_ASM

[BITS 64]

; Local structures to avoid duplicate definitions
struc vma_t_local
    .start      resq 1
    .end        resq 1
    .flags      resq 1
    .next       resq 1
endstruc

struc page_t_local
    .flags      resq 1
    .lock       resq 1
endstruc

PAGE_MIGRATION  equ (1 << 12)       ; Software flag in PTE when Present = 0

; -----------------------------------------------------------------------------
; Section .text
; -----------------------------------------------------------------------------
section .text


; -----------------------------------------------------------------------------
; compact_migrate_page — relocates physical page content and updates mappings
; Input:
;   RDI = source_pfn (relative PFN of source page)
;   RSI = target_pfn (relative PFN of destination page)
; Output:
;   RAX = 1 on success, 0 on failure
; Clobbers: RAX, RCX, RDX, RSI, RDI, R8-R11
; -----------------------------------------------------------------------------
global compact_migrate_page
compact_migrate_page:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp

    mov r12, rdi                    ; R12 = source_pfn
    mov r13, rsi                    ; R13 = target_pfn

    ; 1. Lock the page descriptor matching source_pfn
    mov r8, [pages_array]
    test r8, r8
    jz .skip_lock                   ; Skip locking if pages_array is NULL
    mov rax, r12
    imul rax, 16                    ; RAX = source_pfn * page_t_size (16 bytes)
    lea rbp, [r8 + rax]             ; RBP = page_t* pointer

.lock_page:
    lock bts qword [rbp + page_t_local.lock], 0
    jc .lock_pause
    jmp .lock_acquired
.lock_pause:
    pause
    test qword [rbp + page_t_local.lock], 1
    jnz .lock_pause
    jmp .lock_page
.lock_acquired:
.skip_lock:

    ; Calculate source and target physical addresses
    mov rax, [buddy_start_addr]
    mov r14, r12
    shl r14, 12
    add r14, rax                    ; R14 = source physical address
    
    mov r15, r13
    shl r15, 12
    add r15, rax                    ; R15 = target physical address

    ; 2. Walk the reverse-mapping list. Replace matching PTEs with PAGE_MIGRATION code.
    mov rdx, [vma_list_head]        ; RDX = current VMA
.vma_loop:
    test rdx, rdx
    jz .vma_done

    mov r8, [rdx + vma_t_local.start]   ; R8 = current virtual address (start)
    mov r9, [rdx + vma_t_local.end]     ; R9 = end address (exclusive)

.page_loop:
    cmp r8, r9
    jae .next_vma

    push rdx
    push r8
    push r9
    mov rdi, r8
    mov rsi, 0                      ; active CR3
    call virt_walk_table            ; RAX = leaf PTE pointer, RDX = level
    pop r9
    pop r8
    pop rdx
    test rax, rax
    jz .skip_page

    mov rcx, [rax]
    test rcx, 1                     ; Check present flag
    jz .skip_page

    ; Check if physical address matches source physical address (R14)
    mov rsi, rcx
    mov rdi, 0x000FFFFFFFFFF000     ; physical address mask
    and rsi, rdi
    cmp rsi, r14
    jne .skip_page

    ; Match found! Extract original flags
    mov rsi, rcx
    not rdi                         ; RDI = flag mask
    and rsi, rdi                    ; rsi = original flags (Present = 1)
    and rsi, ~1                     ; Clear Present bit (bit 0 = 0)
    or rsi, PAGE_MIGRATION          ; Set PAGE_MIGRATION bit (bit 12)

    mov [rax], rsi                  ; Write migration entry
    invlpg [r8]                     ; Invalidate TLB entry

.skip_page:
    add r8, 4096
    jmp .page_loop

.next_vma:
    mov rdx, [rdx + vma_t_local.next]
    jmp .vma_loop
.vma_done:

    ; 3. Copy page contents from source_phys (R14) to target_phys (R15)
    xor rcx, rcx
.copy_loop:
    cmp rcx, 512                    ; 512 Qwords = 4096 bytes
    jae .copy_done
    mov rax, [r14 + rcx * 8]
    mov [r15 + rcx * 8], rax
    inc rcx
    jmp .copy_loop
.copy_done:

    ; 4. Update PTE entries to point to the new target_pfn, clearing migration code
    mov rdx, [vma_list_head]        ; RDX = current VMA
.vma_restore_loop:
    test rdx, rdx
    jz .vma_restore_done

    mov r8, [rdx + vma_t_local.start]   ; R8 = current virtual address (start)
    mov r9, [rdx + vma_t_local.end]     ; R9 = end address (exclusive)

.page_restore_loop:
    cmp r8, r9
    jae .next_restore_vma

    push rdx
    push r8
    push r9
    mov rdi, r8
    mov rsi, 0                      ; active CR3
    call virt_walk_table            ; RAX = leaf PTE pointer, RDX = level
    pop r9
    pop r8
    pop rdx
    test rax, rax
    jz .skip_restore_page

    mov rcx, [rax]
    test rcx, 1                     ; Check present flag
    jnz .skip_restore_page          ; If present, it's not a migration entry

    test rcx, PAGE_MIGRATION
    jz .skip_restore_page           ; Not a migration entry

    ; Restore original flags and set target physical address (R15)
    mov rsi, rcx
    and rsi, ~PAGE_MIGRATION        ; Clear PAGE_MIGRATION bit
    or rsi, 1                       ; Set Present = 1

    ; Extract non-address flags from RSI (Present=1)
    mov rdi, 0x000FFFFFFFFFF000
    not rdi
    and rsi, rdi                    ; RSI = original flags

    or rsi, r15                     ; Merge target physical address
    mov [rax], rsi                  ; Restore PTE
    invlpg [r8]                     ; Invalidate TLB entry

.skip_restore_page:
    add r8, 4096
    jmp .page_restore_loop

.next_restore_vma:
    mov rdx, [rdx + vma_t_local.next]
    jmp .vma_restore_loop
.vma_restore_done:

    ; 5. Free the old frame source_phys (R14)
    mov rdi, r14
    call phys_free_page

    ; 6. Unlock the page descriptor
    mov r8, [pages_array]
    test r8, r8
    jz .exit                        ; Skip unlocking if pages_array is NULL
    mov rax, r12
    imul rax, 16
    lea rbp, [r8 + rax]
    mov qword [rbp + page_t_local.lock], 0

    mov rax, 1                      ; Return success
    jmp .exit

.exit:
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

%endif ; LIB_MEM_VIRT_RECLAIM_COMPACTION_ASM
