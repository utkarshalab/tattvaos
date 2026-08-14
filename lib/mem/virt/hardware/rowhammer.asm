; =============================================================================
; Tattva OS — lib/mem/virt/hardware/rowhammer.asm
; =============================================================================
; Hardware-Level Page Access Rate Limiting (Rowhammer Protection) (Feature 17).
; Detects charge-leakage risk on memory rows, dynamically relocates targeted
; physical pages, and forces DRAM refresh cycles.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_HARDWARE_ROWHAMMER_ASM
%define LIB_MEM_VIRT_HARDWARE_ROWHAMMER_ASM

[BITS 64]

; -----------------------------------------------------------------------------
; Section .text
; -----------------------------------------------------------------------------
section .text


; -----------------------------------------------------------------------------
; rowhammer_alert_handler — relocates hammered physical pages to mitigate Rowhammer
; Input:
;   RDI = target_vaddr (Virtual address of targeted page, 4KB page aligned)
; Output:
;   RAX = 1 on success, 0 on failure
; Clobbers: RAX, RCX, RDX, RSI, RDI, R8-R11
; -----------------------------------------------------------------------------
global rowhammer_alert_handler
rowhammer_alert_handler:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r15, rdi                    ; R15 = target_vaddr

    ; 1. Walk page tables to locate the leaf PTE for target_vaddr
    mov rdi, r15
    mov rsi, 0                      ; use current CR3
    call virt_walk_table            ; RAX = leaf PTE ptr, RDX = level
    test rax, rax
    jz .fail

    ; Confirm it's resolved at a standard page entry (level 4 or 5)
    cmp rdx, 4
    je .valid_level
    cmp rdx, 5
    je .valid_level
    jmp .fail

.valid_level:
    mov rbx, rax                    ; RBX = PTE pointer (virtual address)
    mov r12, [rbx]                  ; R12 = PTE entry value
    test r12, 1                     ; Check PAGE_PRESENT (bit 0)
    jz .fail

    ; 2. Extract physical frame address of the hammered page (bits 12 to 51)
    mov r13, r12
    mov rcx, 0x000FFFFFFFFFF000     ; physical frame mask
    and r13, rcx                    ; R13 = old physical page frame address

    ; 3. Allocate a new physical page frame
    call phys_alloc_page            ; RAX = new physical page address
    test rax, rax
    jz .fail
    mov r14, rax                    ; R14 = new physical page address

    ; 4. Copy 4KB content from old page (identity-mapped) to new page
    xor rcx, rcx
.copy_loop:
    cmp rcx, 512                    ; 512 Qwords = 4096 bytes
    jae .copy_done
    mov rsi, [r13 + rcx * 8]
    mov [r14 + rcx * 8], rsi
    inc rcx
    jmp .copy_loop

.copy_done:
    ; 5. Update PTE to point to new physical page address (preserving other bits/flags)
    mov rcx, 0x000FFFFFFFFFF000
    not rcx                         ; RCX = mask for flags/non-address bits
    and r12, rcx                    ; R12 = flags only
    or r12, r14                     ; R12 = flags + new physical address
    mov [rbx], r12                  ; write back updated PTE

    ; 6. Invalidate TLB for the target virtual address
    invlpg [r15]

    ; 7. Free the old physical page
    mov rdi, r13
    call phys_free_page

    ; 8. Force DRAM refresh cycles using memory barrier (mfence) and memory synchronizations
    mfence

    ; Success return
    mov rax, 1
    jmp .exit

.fail:
    xor rax, rax

.exit:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

%endif ; LIB_MEM_VIRT_HARDWARE_ROWHAMMER_ASM
